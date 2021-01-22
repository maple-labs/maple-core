// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;

import "./token/FDT.sol";
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
contract Loan is FDT {
    
    using SafeMathInt     for int256;
    using SignedSafeMath  for int256;
    using SafeMath       for uint256;

    enum State { Live, Active, Matured }  // Live = Created, Active = Drawndown

    State public loanState;  // The current state of this loan, as defined in the State enum below.
    
    IGlobals public globals;  // Maple Globals

    IERC20Details public immutable loanAsset;        // Asset deposited by lenders into the FundingLocker, when funding this loan.
    IERC20Details public immutable collateralAsset;  // Asset deposited by borrower into the CollateralLocker, for collateralizing this loan.

    address public immutable fundingLocker;     // Funding locker - holds custody of loan funds before drawdown    
    address public immutable flFactory;         // Funding locker factory
    address public immutable collateralLocker;  // Collateral locker - holds custody of loan collateral
    address public immutable clFactory;         // Collateral locker factory
    address public immutable borrower;          // Borrower of this loan, responsible for repayments.
    address public immutable repaymentCalc;     // The repayment calculator for this loan.
    address public immutable lateFeeCalc;       // The late fee calculator for this loan.
    address public immutable premiumCalc;       // The premium calculator for this loan.
    address public immutable superFactory;      // The factory that deployed this Loan.

    uint256 public principalOwed;   // The principal owed (initially the drawdown amount).
    uint256 public drawdownAmount;  // The amount the borrower drew down, historical reference for calculators.
    uint256 public nextPaymentDue;  // The unix timestamp due date of next payment.

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
        require(loanState == _state, "Loan:STATE_CHECK");
        _;
    }

    modifier isBorrower() {
        require(msg.sender == borrower, "Loan:MSG_SENDER_NOT_BORROWER");
        _;
    }

    modifier isGovernor() {
        require(msg.sender == globals.governor(), "Loan:MSG_SENDER_NOT_GOVERNOR");
        _;
    }

    event LoanFunded(uint256 amtFunded, address indexed _fundedBy);
    event BalanceUpdated(address who, address token, uint256 balance);
    event Drawdown(uint256 drawdownAmt);
    event PaymentMade(
        uint totalPaid,
        uint principalPaid,
        uint interestPaid,
        uint paymentsRemaining,
        uint principalOwed,
        uint nextPaymentDue,
        bool latePayment
    );

    /**
        @dev Constructor for a Loan.
        @param  _borrower        Will receive the funding when calling drawdown(), is also responsible for repayments.
        @param  _loanAsset       The asset _borrower is requesting funding in.
        @param  _collateralAsset The asset provided as collateral by _borrower.
        @param  _flFactory       Factory to instantiate FundingLocker with.
        @param  _clFactory       Factory to instantiate CollateralLocker with.
        @param  _globals         The MapleGlobals contract.
        @param  specs            Contains specifications for this loan.
                specs[0] = apr
                specs[1] = termDays
                specs[2] = paymentIntervalDays
                specs[3] = minRaise
                specs[4] = collateralRatio
                specs[5] = fundingPeriodDays
        @param  calcs            The calculators used for the loan.
                calcs[0] = repaymentCalc
                calcs[1] = lateFeeCalc
                calcs[2] = premiumCalc
    */
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
        FDT(
            string(abi.encodePacked("Maple Loan Vault Token ", tUUID)),
            string(abi.encodePacked("ML", tUUID)),
            _loanAsset
        )
        public
    {
        borrower        = _borrower;
        loanAsset       = IERC20Details(_loanAsset);
        collateralAsset = IERC20Details(_collateralAsset);
        flFactory       = _flFactory;
        clFactory       = _clFactory;
        globals         = IGlobals(_globals);
        createdAt       = block.timestamp;

        // Perform validity cross-checks.
        require(IGlobals(_globals).isValidLoanAsset(_loanAsset),             "Loan:INVALID_LOAN_ASSET");
        require(IGlobals(_globals).isValidCollateralAsset(_collateralAsset), "Loan:INVALID_COLLATERAL_ASSET");

        require(specs[2] != 0,               "Loan:PAYMENT_INTERVAL_DAYS_EQ_ZERO");
        require(specs[1].mod(specs[2]) == 0, "Loan:INVALID_TERM_AND_PAYMENT_INTERVAL_DIVISION");
        require(specs[3] > 0,                "Loan:MIN_RAISE_EQ_ZERO");
        require(specs[5] > 0,                "Loan:FUNDING_PERIOD_EQ_ZERO");

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
        superFactory           = msg.sender;

        // Deploy locker
        collateralLocker = ICollateralLockerFactory(_clFactory).newLocker(_collateralAsset);
        fundingLocker    = IFundingLockerFactory(_flFactory).newLocker(_loanAsset);
    }

    /**
        @dev Update the maple globals contract
        @param  newGlobals Address of new maple globals contract
    */
    function setGlobals(address newGlobals) external isGovernor {
        globals = IGlobals(newGlobals);
    }

    /**
        @dev Fund this loan and mint debt tokens for mintTo.
        @param  amt    Amount to fund the loan.
        @param  mintTo Address that debt tokens are minted to.
    */
    // TODO: Update this function signature to use (address, uint)
    function fundLoan(uint256 amt, address mintTo) external isState(State.Live) {
        
        require(loanAsset.transferFrom(msg.sender, fundingLocker, amt), "Loan:INSUFFICIENT_APPROVAL_FUND_LOAN");

        uint256 wad = _toWad(amt);  // Convert to WAD precision
        _mint(mintTo, wad);         // Mint FDT to `mintTo` i.e Debt locker contract.

        emit LoanFunded(amt, mintTo);
        emit BalanceUpdated(fundingLocker, address(loanAsset), loanAsset.balanceOf(fundingLocker));
    }

    /**
        @dev Drawdown funding from FundingLocker, post collateral, and transition loanState from Funding to Active.
        @param  amt Amount of loanAsset borrower draws down, remainder is returned to Loan.
    */
    function drawdown(uint256 amt) external isState(State.Live) isBorrower {

        IGlobals _globals = globals;

        IFundingLocker _fundingLocker = IFundingLocker(fundingLocker);

        require(amt >= minRaise,                           "Loan:DRAWDOWN_AMT_LT_MIN_RAISE");
        require(amt <= loanAsset.balanceOf(fundingLocker), "Loan:DRAWDOWN_AMT_GT_FUNDED_AMT");

        // Update the principal owed and drawdown amount for this loan.
        principalOwed  = amt;
        drawdownAmount = amt;

        loanState = State.Active;

        // Transfer the required amount of collateral for drawdown from Borrower to CollateralLocker.
        require(
            collateralAsset.transferFrom(borrower, collateralLocker, collateralRequiredForDrawdown(amt)), 
            "Loan:INSUFFICIENT_COLLATERAL_APPROVAL"
        );

        // Transfer funding amount from FundingLocker to Borrower, then drain remaining funds to Loan.
        uint treasuryFee = _globals.treasuryFee();
        uint investorFee = _globals.investorFee();

        address treasury = _globals.mapleTreasury();

        // Update investorFee locally.
        feePaid             = amt.mul(investorFee).div(10000);
        uint256 treasuryAmt = amt.mul(treasuryFee).div(10000);  // Calculate amt to send to MapleTreasury

        require(_fundingLocker.pull(treasury,      treasuryAmt),                       "Loan:TREASURY_FEE_PULL");  // Send treasuryFee directly to MapleTreasury
        require(_fundingLocker.pull(address(this), feePaid),                           "Loan:INVESTOR_FEE_PULL");  // Pull investorFee into this Loan.
        require(_fundingLocker.pull(borrower,      amt.sub(treasuryAmt).sub(feePaid)), "Loan:BORROWER_PULL");      // Transfer drawdown amount to Borrower.

        // Update excessReturned locally.
        excessReturned = loanAsset.balanceOf(fundingLocker);

        // Drain remaining funds from FundingLocker.
        require(_fundingLocker.drain(), "Loan:DRAIN");

        emit BalanceUpdated(collateralLocker, address(collateralAsset), collateralAsset.balanceOf(collateralLocker));
        emit BalanceUpdated(fundingLocker,    address(loanAsset),       loanAsset.balanceOf(fundingLocker));
        emit BalanceUpdated(address(this),    address(loanAsset),       loanAsset.balanceOf(address(this)));
        emit BalanceUpdated(treasury,         address(loanAsset),       loanAsset.balanceOf(treasury));

        emit Drawdown(amt);
    }

    /**
        @dev Make the next payment for this loan.
    */
    function makePayment() public isState(State.Active) {
        (uint256 total, uint256 principal, uint256 interest,) = getNextPayment();

        require(loanAsset.transferFrom(msg.sender, address(this), total), "Loan:MAKE_PAYMENT_TRANSFER_FROM");

        // Update internal accounting variables.
        principalOwed  = principalOwed.sub(principal);
        principalPaid  = principalPaid.add(principal);
        interestPaid   = interestPaid.add(interest);
        nextPaymentDue = nextPaymentDue.add(paymentIntervalSeconds);
        paymentsRemaining--;

        emit PaymentMade(
            total, 
            principal, 
            interest, 
            paymentsRemaining, 
            principalOwed, 
            paymentsRemaining > 0 ? nextPaymentDue : 0, 
            false
        );

        // Handle final payment.
        // TODO: Identify any other variables worth resetting on final payment.
        if (paymentsRemaining == 0) {
            loanState = State.Matured;
            nextPaymentDue = 0;
            require(ICollateralLocker(collateralLocker).pull(borrower, collateralAsset.balanceOf(collateralLocker)), "Loan:COLLATERAL_PULL");
            emit BalanceUpdated(collateralLocker, address(collateralAsset), collateralAsset.balanceOf(collateralLocker));
        }

        updateFundsReceived();

        emit BalanceUpdated(address(this), address(loanAsset),  loanAsset.balanceOf(address(this)));
    }

    /**
        @dev Returns information on next payment amount.
        @return [0] = Principal + Interest
                [1] = Principal 
                [2] = Interest
                [3] = Payment Due Date
    */
    function getNextPayment() public view returns(uint256, uint256, uint256, uint256) {

        IGlobals _globals = globals;

        (
            uint256 total, 
            uint256 principal, 
            uint256 interest
        ) = IRepaymentCalc(repaymentCalc).getNextPayment(address(this));

        if (block.timestamp > nextPaymentDue && block.timestamp <= nextPaymentDue.add(_globals.gracePeriod())) {
            (
                uint256 totalExtra, 
                uint256 principalExtra, 
                uint256 interestExtra
            ) = ILateFeeCalc(lateFeeCalc).getLateFee(address(this));

            total     = total.add(totalExtra);
            interest  = interest.add(interestExtra);
            principal = principal.add(principalExtra);
        } 
        else if (block.timestamp > nextPaymentDue.add(_globals.gracePeriod())) {
            // TODO: Implement handling a default scenario.
            // TODO: Implement handling Pool Delegate (investor) early grace period default trigger.
            // TODO: Implement handling public grace period default trigger.
        }
        
        return (total, principal, interest, nextPaymentDue);
    }

    /**
        @dev Make the full payment for this loan, a.k.a. "calling" the loan.
    */
    function makeFullPayment() public isState(State.Active) {
        (uint256 total, uint256 principal, uint256 interest) = getFullPayment();

        require(loanAsset.transferFrom(msg.sender, address(this), total),"Loan:MAKE_FULL_PAYMENT_TRANSFER_FROM");

        loanState = State.Matured;

        // Update internal accounting variables.
        // TODO: Identify any other variables worth resetting on full payment.
        principalOwed     = 0;
        paymentsRemaining = 0;
        principalPaid     = principalPaid.add(principal);
        interestPaid      = interestPaid.add(interest);

        updateFundsReceived();

        emit PaymentMade(
            total,
            principal,
            interest,
            paymentsRemaining,
            principalOwed,
            0,
            false
        );
        emit BalanceUpdated(address(this), address(loanAsset),  loanAsset.balanceOf(address(this)));
    }

    /**
        @dev Returns information on full payment amount.
        @return [0] = Principal + Interest
                [1] = Principal 
                [2] = Interest
                [3] = Payment Due Date
    */
    function getFullPayment() public view returns(uint256, uint256, uint256) {
        (uint256 total, uint256 principal, uint256 interest) = IPremiumCalc(premiumCalc).getPremiumPayment(address(this));
        return (total, principal, interest);
    }

    /**
        @dev Helper for calculating collateral required to drawdown amt.
        @param  amt The amount of loanAsset to drawdown from FundingLocker.
        @return The amount of collateralAsset required to post in CollateralLocker for given drawdown amt.
    */
    function collateralRequiredForDrawdown(uint256 amt) public view returns(uint256) {

        IGlobals _globals = globals;

        uint256 wad = _toWad(amt);  // Convert to WAD precision.

        // Fetch value of collateral and funding asset.
        uint256 loanAssetPrice  = _globals.getPrice(address(loanAsset));
        uint256 collateralPrice = _globals.getPrice(address(collateralAsset));

        // Calculate collateral required.
        uint256 collateralRequiredUSD = loanAssetPrice.mul(wad).mul(collateralRatio).div(10000);
        uint256 collateralRequiredWEI = collateralRequiredUSD.div(collateralPrice);
        uint256 collateralRequiredFIN = collateralRequiredWEI.div(10 ** (18 - collateralAsset.decimals()));

        return collateralRequiredFIN;
    }

    function _toWad(uint256 amt) internal view returns(uint256) {
        return amt.mul(10 ** 18).div(10 ** loanAsset.decimals());
    }
}
