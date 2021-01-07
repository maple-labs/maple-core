// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./token/FundsDistributionToken.sol";
import "./interfaces/IGlobals.sol";
import "./interfaces/IFundingLocker.sol";
import "./interfaces/IFundingLockerFactory.sol";
import "./interfaces/ICollateralLocker.sol";
import "./interfaces/ICollateralLockerFactory.sol";
import "./interfaces/IERC20Details.sol";
import "./interfaces/IRepaymentCalc.sol";
import "./interfaces/ILateFeeCalc.sol";
import "./interfaces/IPremiumCalc.sol";

/// @title Loan is the core loan vault contract.
contract Loan is FundsDistributionToken {
    
    using SafeMathInt     for int256;
    using SignedSafeMath  for int256;
    using SafeMath       for uint256;

    enum State { Live, Active, Matured } // Live = Created, Active = Drawndown

    State public loanState;  // The current state of this loan, as defined in the State enum below.

    address public immutable loanAsset;         // Asset deposited by lenders into the FundingLocker, when funding this loan.
    address public immutable collateralAsset;   // Asset deposited by borrower into the CollateralLocker, for collateralizing this loan.
    address public immutable fundingLocker;     // Funding locker - holds custody of loan funds before drawdown    
    address public immutable flFactory;         // Funding locker factory
    address public immutable collateralLocker;  // Collateral locker - holds custody of loan collateral
    address public immutable clFactory;         // Collateral locker factory
    address public immutable borrower;          // Borrower of this loan, responsible for repayments.
    address public immutable globals;           // Maple Globals
    address public immutable repaymentCalc;     // The repayment calculator for this loan.
    address public immutable lateFeeCalc;       // The late fee calculator for this loan.
    address public immutable premiumCalc;       // The premium calculator for this loan.

    uint256 public principalOwed;      // The principal owed (initially the drawdown amount).
    uint256 public drawdownAmount;     // The amount the borrower drew down, historical reference for calculators.
    uint256 public nextPaymentDue;     // The unix timestamp due date of next payment.

    // Loan specifications
    uint256 public apr;         
    uint256 public paymentsRemaining;
    uint256 public termDays;
    uint256 public paymentIntervalSeconds; 
    uint256 public minRaise;
    uint256 public collateralRatio;
    uint256 public fundingPeriodSeconds;
    uint256 public createdAt;

    // Accounting variables
    uint256 public principalPaid;
    uint256 public interestPaid;
    uint256 public feePaid;
    uint256 public excessReturned;

    modifier isState(State _state) {
        require(loanState == _state, "Loan::ERR_FAIL_STATE_CHECK");
        _;
    }

    modifier isBorrower() {
        require(msg.sender == borrower, "Loan::ERR_MSG_SENDER_NOT_BORROWER");
        _;
    }

    event LoanFunded(uint256 amtFunded, address indexed _fundedBy);
    event BalanceUpdated(address who, address token, uint256 balance);

    /// @notice Constructor for loan vault.
    /// @param _borrower Address of borrower
    /// @param _loanAsset The asset borrower is requesting funding in.
    /// @param _collateralAsset The asset provided as collateral by the borrower.
    /// @param _flFactory Factory to instantiate FundingLocker through.
    /// @param _clFactory Factory to instantiate CollateralLocker through.
    /// @param _globals Address of the IGlobals(globals).sol contract.
    /// @param specs The specifications of the loan.
    ///        specs[0] = apr
    ///        specs[1] = termDays
    ///        specs[2] = paymentIntervalDays
    ///        specs[3] = minRaise
    ///        specs[4] = collateralRatio
    ///        specs[5] = fundingPeriodDays
    /// @param calcs The calculators used for the loan.
    ///        calcs[0] = repaymentCalc
    ///        calcs[1] = lateFeeCalc
    ///        calcs[2] = premiumCalc
    constructor(
        address _borrower,
        address _loanAsset,
        address _collateralAsset,
        address _flFactory,
        address _clFactory,
        address _globals,
        uint256[6] memory specs,
        address[3] memory calcs,
        string memory tUUID
    )
        FundsDistributionToken(
            string(abi.encodePacked("Maple Loan Vault Token ", tUUID)),
            string(abi.encodePacked("ML", tUUID)),
            _loanAsset
        )
        public
    {
        require(
            address(_loanAsset) != address(0),
            "Loan::constructor:ERR_INVALID_FUNDS_TOKEN_ADDRESS"
        );

        borrower        = _borrower;
        loanAsset       = _loanAsset;
        collateralAsset = _collateralAsset;
        flFactory       = _flFactory;
        clFactory       = _clFactory;
        globals         = _globals;
        createdAt       = block.timestamp;

        // Perform validity cross-checks.
        require(
            IGlobals(_globals).isValidLoanAsset(_loanAsset),
            "Loan::constructor:ERR_INVALID_ASSET_REQUESTED"
        );
        require(
            IGlobals(_globals).isValidCollateralAsset(_collateralAsset),
            "Loan::constructor:ERR_INVALID_ASSET_REQUESTED"
        );
        require(specs[2] != 0,               "Loan::constructor:ERR_PAYMENT_INTERVAL_DAYS_EQUALS_ZERO");
        require(specs[1].mod(specs[2]) == 0, "Loan::constructor:ERR_INVALID_TERM_AND_PAYMENT_INTERVAL_DIVISION");
        require(specs[3] > 0,                "Loan::constructor:ERR_MIN_RAISE_EQUALS_ZERO");
        require(specs[5] > 0,                "Loan::constructor:ERR_FUNDING_PERIOD_EQUALS_ZERO");

        // Update state variables.
        apr                    = specs[0];
        termDays               = specs[1];
        paymentsRemaining      = specs[1].div(specs[2]);
        paymentIntervalSeconds = specs[2].mul(1 days);
        minRaise               = specs[3];
        collateralRatio        = specs[4];
        fundingPeriodSeconds   = specs[5].mul(1 days);
        repaymentCalc          = calcs[0];
        lateFeeCalc            = calcs[1];
        premiumCalc            = calcs[2];
        nextPaymentDue         = createdAt.add(paymentIntervalSeconds);

        // Deploy locker
        collateralLocker = ICollateralLockerFactory(_clFactory).newLocker(_collateralAsset);
        fundingLocker    = IFundingLockerFactory(_flFactory).newLocker(_loanAsset);
    }

    /**
     * @notice Fund this loan and mint LoanTokens.
     * @param amt Amount of _loanAsset to fund the loan for.
     * @param mintTo The address to mint LoanTokens for.
     */
    // TODO: Update this function signature to use (address, uint)
    function fundLoan(uint256 amt, address mintTo) external isState(State.Live) {
        // TODO: Consider testing decimal precision difference: loanAsset <> FundsToken
        require(
            IERC20(loanAsset).transferFrom(msg.sender, fundingLocker, amt),
            "Loan::fundLoan:ERR_INSUFFICIENT_APPROVED_FUNDS"
        );
        _mint(mintTo, amt);

        emit LoanFunded(amt, mintTo);
        emit BalanceUpdated(fundingLocker, loanAsset, IERC20(loanAsset).balanceOf(fundingLocker));
    }

    /// @notice Returns the balance of loanAsset in the FundingLocker.
    /// @return The balance of FundingLocker.
    function getFundingLockerBalance() view public returns(uint) {
        return IERC20(loanAsset).balanceOf(fundingLocker);
    }

    /// @notice Returns the balance of _collateralAsset in the CollateralLocker.
    /// @return The balance of CollateralLocker.
    function getCollateralLockerBalance() view public returns(uint) {
        return IERC20(collateralAsset).balanceOf(collateralLocker);
    }

    /// @notice End funding period by claiming funds, posting collateral, transitioning loanState from Funding to Active.
    /// @param amt Amount of loanAsset borrower will claim, remainder is returned to Loan.
    function drawdown(uint256 amt) external isState(State.Live) isBorrower {

        // TODO: Change endFunding to drawdown in err message
        require(
            amt >= minRaise, 
            "Loan::endFunding::ERR_DRAWDOWN_AMOUNT_BELOW_MIN_RAISE"
        );
        require(
            amt <= IERC20(loanAsset).balanceOf(fundingLocker), 
            "Loan::endFunding::ERR_DRAWDOWN_AMOUNT_ABOVE_FUNDING_LOCKER_BALANCE"
        );

        // Update the principal owed and drawdown amount for this loan.
        principalOwed  = amt;
        drawdownAmount = amt;

        loanState = State.Active;

        // Transfer the required amount of collateral for drawdown from Borrower to CollateralLocker.
        require(
            IERC20(collateralAsset).transferFrom(borrower, collateralLocker, collateralRequiredForDrawdown(amt)), 
            "Loan::endFunding:ERR_COLLATERAL_TRANSFER_FROM_APPROVAL_OR_BALANCE"
        );

        // Transfer funding amount from FundingLocker to Borrower, then drain remaining funds to Loan.
        uint treasuryFee = IGlobals(globals).treasuryFee();
        uint investorFee = IGlobals(globals).investorFee();

        address treasury = IGlobals(globals).mapleTreasury();

        // Send treasuryFee directly to MapleTreasury
        require(
           IFundingLocker(fundingLocker).pull(treasury, amt.mul(treasuryFee).div(10000)), 
            "Loan::drawdown:CRITICAL_ERR_PULL"
        );

        // Update investorFee locally.
        feePaid = amt.mul(investorFee).div(10000);

        // Pull investorFee into this Loan.
        require(IFundingLocker(fundingLocker).pull(address(this), feePaid), "Loan::drawdown:CRITICAL_ERR_PULL");

        // Transfer drawdown amount to Borrower.
        require(
            IFundingLocker(fundingLocker).pull(borrower, amt.mul(10000 - investorFee - treasuryFee).div(10000)), 
            "Loan::drawdown:CRITICAL_ERR_PULL"
        );

        // Update excessReturned locally.
        excessReturned = IERC20(loanAsset).balanceOf(fundingLocker);

        // Drain remaining funds from FundingLocker.
        require(IFundingLocker(fundingLocker).drain(), "Loan::endFunding:ERR_DRAIN");

        emit BalanceUpdated(collateralLocker, collateralAsset, IERC20(collateralAsset).balanceOf(collateralLocker));
        emit BalanceUpdated(fundingLocker,    loanAsset,       IERC20(loanAsset).balanceOf(fundingLocker));
        emit BalanceUpdated(address(this),    loanAsset,       IERC20(loanAsset).balanceOf(address(this)));
        emit BalanceUpdated(treasury,         loanAsset,       IERC20(loanAsset).balanceOf(treasury));
    }

    /// @notice Make the next payment for this loan.
    function makePayment() public isState(State.Active) {
        if (block.timestamp <= nextPaymentDue) {

            (
                uint256 paymentAmount,
                uint256 principal,
                uint256 interest
            ) = IRepaymentCalc(repaymentCalc).getNextPayment(address(this));

            require(
                IERC20(loanAsset).transferFrom(msg.sender, address(this), paymentAmount),
                "Loan::makePayment:ERR_LACK_APPROVAL_OR_BALANCE"
            );

            // Update internal accounting variables.
            principalOwed  = principalOwed.sub(principal);
            principalPaid  = principalPaid.add(principal);
            interestPaid   = interestPaid.add(interest);
            nextPaymentDue = nextPaymentDue.add(paymentIntervalSeconds);
            paymentsRemaining--;
        }
        else if (block.timestamp <= nextPaymentDue.add(IGlobals(globals).gracePeriod())) {
            (
                uint256 paymentAmount,
                uint256 principal,
                uint256 interest
            ) = IRepaymentCalc(repaymentCalc).getNextPayment(address(this));
            // TODO: Identify whether principalExtra is needed for lateFee (if only interest needeD).
            (
                uint256 paymentAmountExtra,
                uint256 principalExtra,
                uint256 interestExtra
            ) = ILateFeeCalc(lateFeeCalc).getLateFee(address(this));

            require(
                IERC20(loanAsset).transferFrom(msg.sender, address(this), paymentAmount.add(paymentAmountExtra)),
                "Loan::makePayment:ERR_LACK_APPROVAL_OR_BALANCE"
            );

            // Update internal accounting variables.
            principalOwed  = principalOwed.sub(principal);
            principalPaid  = principalPaid.add(principal).add(principalExtra);
            interestPaid   = interestPaid.add(interest).add(interestExtra);
            nextPaymentDue = nextPaymentDue.add(paymentIntervalSeconds);
            paymentsRemaining--;
        }
        else {
            // TODO: Trigger default, or other action as per business requirements.
        }

        // Handle final payment.
        // TODO: Identify any other variables worth resetting on final payment.
        if (paymentsRemaining == 0) {
            loanState = State.Matured;
            ICollateralLocker(collateralLocker).pull(borrower, getCollateralLockerBalance());

            emit BalanceUpdated(collateralLocker, collateralAsset, IERC20(collateralAsset).balanceOf(collateralLocker));
        }

        updateFundsReceived();

        emit BalanceUpdated(address(this), loanAsset,  IERC20(loanAsset).balanceOf(address(this)));
    }

    /// @notice Returns the next payment amounts.
    /// @return [0] = Principal + Interest, [1] = Principal, [2] = Interest, [3] Due By Timestamp
    function getNextPayment() public view returns(uint256, uint256, uint256, uint256) {
        (
            uint256 total, 
            uint256 principal,
            uint256 interest
        ) = IRepaymentCalc(repaymentCalc).getNextPayment(address(this));
        return (total, principal, interest, nextPaymentDue);
    }

    /// @notice Makes the full payment for this loan, a.k.a. "calling" the loan.
    function makeFullPayment() public isState(State.Active) {
        (
            uint256 total, 
            uint256 principal,
            uint256 interest
        ) = IPremiumCalc(premiumCalc).getPremiumPayment(address(this));

        require(
            IERC20(loanAsset).transferFrom(msg.sender, address(this), total),
            "Loan::makeFullPayment:ERR_LACK_APPROVAL_OR_BALANCE"
        );

        loanState = State.Matured;

        // Update internal accounting variables.
        // TODO: Identify any other variables worth resetting on full payment.
        principalOwed     = 0;
        paymentsRemaining = 0;
        principalPaid     = principalPaid.add(principal);
        interestPaid      = interestPaid.add(interest);

        updateFundsReceived();

        emit BalanceUpdated(address(this), loanAsset,  IERC20(loanAsset).balanceOf(address(this)));
    }

    /// @notice Returns the payment amount when paying off the loan early.
    /// @return [0] = Principal + Interest, [1] = Principal, [2] = Interest
    function getFullPayment() public view returns(uint256, uint256, uint256) {
        (
            uint256 total, 
            uint256 principal,
            uint256 interest
        ) = IPremiumCalc(premiumCalc).getPremiumPayment(address(this));
        return (total, principal, interest);
    }


    /// @notice Viewer helper for calculating collateral required to drawdown funding.
    /// @param amt The amount of loanAsset to drawdown from FundingLocker.
    /// @return The amount of collateralAsset required to post for given amt.
    function collateralRequiredForDrawdown(uint256 amt) public view returns(uint256) {

        // Fetch value of collateral and funding asset.
        uint256 requestPrice    = IGlobals(globals).getPrice(loanAsset);
        uint256 collateralPrice = IGlobals(globals).getPrice(collateralAsset);

        /*
            Current values fed into ChainLink oracles (8 decimals, based on Kovan values)
            DAI_USD  == 100232161
            USDC_USD == 100232161
            WETH_USD == 59452607912
            WBTC_USD == 1895510185012

            requestPrice(DAI || USDC) = 100232161
            collateralPrice(wBTC) = 1895510185012
            collateralPrice(wETH) = 59452607912
        */

        uint256 collateralRequiredUSD = requestPrice.mul(amt).mul(collateralRatio).div(10000);
        uint256 collateralRequiredWEI = collateralRequiredUSD.div(collateralPrice);
        uint256 collateralRequiredFIN = collateralRequiredWEI.div(10 ** (18 - IERC20Details(collateralAsset).decimals()));

        return collateralRequiredFIN;
    }
}
