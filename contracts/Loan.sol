// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;

import "./token/FDT.sol";
import "./interfaces/IGlobals.sol";
import "./interfaces/IFundingLocker.sol";
import "./interfaces/IFundingLockerFactory.sol";
import "./interfaces/ICollateralLocker.sol";
import "./interfaces/ICollateralLockerFactory.sol";
import "./interfaces/IERC20Details.sol";
import "./interfaces/ILoanFactory.sol";
import "./interfaces/IRepaymentCalc.sol";
import "./interfaces/ILateFeeCalc.sol";
import "./interfaces/IPremiumCalc.sol";
import "./interfaces/IUniswapRouter.sol";

/// @title Loan is the core loan vault contract.
contract Loan is FDT {
    
    using SafeMathInt     for int256;
    using SignedSafeMath  for int256;
    using SafeMath        for uint256;

    /**
        Live = The loan has been initialized and is open for funding (assuming funding period not ended).
        Active = The loan has been drawdown and the borrower is making payments.
        Matured = The loan is fully paid off and has "matured".
        Liquidated = The loan has been liquidated.
    */
    enum State { Live, Active, Matured, Liquidated }

    State public loanState;  // The current state of this loan, as defined in the State enum below.

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
    uint256 public defaultSuffered;
    
    // Liquidation variables
    uint256 public amountLiquidated;
    uint256 public amountRecovered;
    uint256 public liquidationExcess;

    modifier isState(State _state) {
        require(loanState == _state, "Loan:STATE_CHECK");
        _;
    }

    modifier isBorrower() {
        require(msg.sender == borrower, "Loan:MSG_SENDER_NOT_BORROWER");
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
    event Liquidation(
        uint collateralSwapped,
        uint loanAssetReturned,
        uint liquidationExcess,
        uint defaultSuffered
    );

    /**
        @dev Constructor for a Loan.
        @param  _borrower        Will receive the funding when calling drawdown(), is also responsible for repayments.
        @param  _loanAsset       The asset _borrower is requesting funding in.
        @param  _collateralAsset The asset provided as collateral by _borrower.
        @param  _flFactory       Factory to instantiate FundingLocker with.
        @param  _clFactory       Factory to instantiate CollateralLocker with.
        @param  specs            Contains specifications for this loan.
                specs[0] = apr
                specs[1] = termDays
                specs[2] = paymentIntervalDays (aka PID)
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
        createdAt       = block.timestamp;

        IGlobals globals = _globals(msg.sender);

        // Perform validity cross-checks.
        require(globals.isValidLoanAsset(_loanAsset),             "Loan:INVALID_LOAN_ASSET");
        require(globals.isValidCollateralAsset(_collateralAsset), "Loan:INVALID_COLLATERAL_ASSET");

        require(specs[2] != 0,               "Loan:PID_EQ_ZERO");
        require(specs[1].mod(specs[2]) == 0, "Loan:INVALID_TERM_DAYS");
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
        @dev Fund this loan and mint debt tokens for mintTo.
        @param  amt    Amount to fund the loan.
        @param  mintTo Address that debt tokens are minted to.
    */
    // TODO: Update this function signature to use (address, uint)
    function fundLoan(uint256 amt, address mintTo) external isState(State.Live) {
        
        _checkValidTransferFrom(loanAsset.transferFrom(msg.sender, fundingLocker, amt));

        uint256 wad = _toWad(amt);  // Convert to WAD precision
        _mint(mintTo, wad);         // Mint FDT to `mintTo` i.e Debt locker contract.

        emit LoanFunded(amt, mintTo);
        emit BalanceUpdated(fundingLocker, address(loanAsset), _getFundingLockerBalance());
    }

    /**
        @dev Drawdown funding from FundingLocker, post collateral, and transition loanState from Funding to Active.
        @param  amt Amount of loanAsset borrower draws down, remainder is returned to Loan.
    */
    function drawdown(uint256 amt) external isState(State.Live) isBorrower {

        IGlobals globals = _globals(superFactory);

        IFundingLocker _fundingLocker = IFundingLocker(fundingLocker);

        require(amt >= minRaise,                   "Loan:DRAWDOWN_AMT_LT_MIN_RAISE");
        require(amt <= _getFundingLockerBalance(), "Loan:DRAWDOWN_AMT_GT_FUNDED_AMT");

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
        uint treasuryFee = globals.treasuryFee();
        uint investorFee = globals.investorFee();

        address treasury = globals.mapleTreasury();

        // Update investorFee locally.
        feePaid             = amt.mul(investorFee).div(10000);
        uint256 treasuryAmt = amt.mul(treasuryFee).div(10000);  // Calculate amt to send to MapleTreasury

        require(_fundingLocker.pull(treasury,      treasuryAmt),                       "Loan:TREASURY_FEE_PULL");  // Send treasuryFee directly to MapleTreasury
        require(_fundingLocker.pull(address(this), feePaid),                           "Loan:INVESTOR_FEE_PULL");  // Pull investorFee into this Loan.
        require(_fundingLocker.pull(borrower,      amt.sub(treasuryAmt).sub(feePaid)), "Loan:BORROWER_PULL");      // Transfer drawdown amount to Borrower.

        // Update excessReturned locally.
        excessReturned = _getFundingLockerBalance();

        // Drain remaining funds from FundingLocker.
        require(_fundingLocker.drain(), "Loan:DRAIN");

        emit BalanceUpdated(collateralLocker, address(collateralAsset), _getCollateralLockerBalance());
        emit BalanceUpdated(fundingLocker,    address(loanAsset),       _getFundingLockerBalance());
        emit BalanceUpdated(address(this),    address(loanAsset),       loanAsset.balanceOf(address(this)));
        emit BalanceUpdated(treasury,         address(loanAsset),       loanAsset.balanceOf(treasury));

        emit Drawdown(amt);
    }

    /**
        @dev Triggers default flow for loan, liquidating all collateral and updating accounting.
    */
    function _triggerDefault() internal {

        // Pull collateralAsset from collateralLocker.
        IUniswapRouter uniswap = IUniswapRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        uint256 liquidationAmt = _getCollateralLockerBalance();
        require(ICollateralLocker(collateralLocker).pull(address(this), liquidationAmt), "Loan:COLLATERAL_PULL");

        // Swap collateralAsset for loanAsset.
        collateralAsset.approve(address(uniswap), liquidationAmt);

        address[] memory path = new address[](2);
        path[0] = address(collateralAsset);
        path[1] = address(loanAsset);

        // TODO: Consider oracles for 2nd parameter below.
        uint[] memory returnAmounts = uniswap.swapExactTokensForTokens(
            collateralAsset.balanceOf(address(this)),
            0, // The minimum amount of output tokens that must be received for the transaction not to revert.
            path,
            address(this),
            block.timestamp + 1000 // Unix timestamp after which the transaction will revert.
        );

        amountLiquidated = returnAmounts[0];
        amountRecovered  = returnAmounts[1];

        // Reduce principal owed by amount received (as much as is required for principal owed == 0).
        if (principalOwed <= amountRecovered) {
            liquidationExcess = amountLiquidated.sub(principalOwed);
            principalOwed = 0;
            loanAsset.transfer(borrower, liquidationExcess); // Send excess to Borrower.
        }
        // If principal owed >  0 after settlement ... all loanAsset remains in Loan.
        else {
            principalOwed   = principalOwed.sub(amountRecovered);
            defaultSuffered = principalOwed;
        }

        // Call updateFundsReceived() to snapshot payout.
        updateFundsReceived();

        // Transition loanState to Liquidated.
        loanState = State.Liquidated;

        // Emit liquidation event.
        emit Liquidation(
            returnAmounts[0],  // collateralSwapped
            returnAmounts[1],  // loanAssetReturned
            liquidationExcess,
            defaultSuffered
        );

    }

    /**
        @dev Trigger a default. Does nothing if block.timestamp <= nextPaymentDue + gracePeriod.
    */
    function triggerDefault() isState(State.Active) external {
        if (block.timestamp > nextPaymentDue.add(_globals(superFactory).gracePeriod())) {
            _triggerDefault();
        }
    }

    /**
        @dev Make the next payment for this loan.
    */
    function makePayment() external isState(State.Active) {

        (uint256 total, uint256 principal, uint256 interest,) = getNextPayment();

        _checkValidTransferFrom(loanAsset.transferFrom(msg.sender, address(this), total));

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
            require(ICollateralLocker(collateralLocker).pull(borrower, _getCollateralLockerBalance()), "Loan:COLLATERAL_PULL");
            emit BalanceUpdated(collateralLocker, address(collateralAsset), _getCollateralLockerBalance());
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

        IGlobals globals = _globals(superFactory);

        (
            uint256 total, 
            uint256 principal, 
            uint256 interest
        ) = IRepaymentCalc(repaymentCalc).getNextPayment(address(this));

        if (block.timestamp > nextPaymentDue && block.timestamp <= nextPaymentDue.add(globals.gracePeriod())) {
            (
                uint256 totalExtra, 
                uint256 principalExtra, 
                uint256 interestExtra
            ) = ILateFeeCalc(lateFeeCalc).getLateFee(address(this));

            total     = total.add(totalExtra);
            interest  = interest.add(interestExtra);
            principal = principal.add(principalExtra);
        }
        
        return (total, principal, interest, nextPaymentDue);
    }

    /**
        @dev Make the full payment for this loan, a.k.a. "calling" the loan.
    */
    function makeFullPayment() public isState(State.Active) {
        (uint256 total, uint256 principal, uint256 interest) = getFullPayment();

        _checkValidTransferFrom(loanAsset.transferFrom(msg.sender, address(this), total));

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

        IGlobals globals = _globals(superFactory);

        uint256 wad = _toWad(amt);  // Convert to WAD precision.

        // Fetch value of collateral and funding asset.
        uint256 loanAssetPrice  = globals.getPrice(address(loanAsset));
        uint256 collateralPrice = globals.getPrice(address(collateralAsset));

        // Calculate collateral required.
        uint256 collateralRequiredUSD = loanAssetPrice.mul(wad).mul(collateralRatio).div(10000);
        uint256 collateralRequiredWEI = collateralRequiredUSD.div(collateralPrice);
        uint256 collateralRequiredFIN = collateralRequiredWEI.div(10 ** (18 - collateralAsset.decimals()));

        return collateralRequiredFIN;
    }

    function _toWad(uint256 amt) internal view returns(uint256) {
        return amt.mul(10 ** 18).div(10 ** loanAsset.decimals());
    }
    	
    function _checkValidTransferFrom(bool isValid) internal {
        require(isValid, "Loan:INSUFFICIENT_APPROVAL");
    }

    function _globals(address loanFactory) internal view returns (IGlobals) {
        return IGlobals(ILoanFactory(loanFactory).globals());
    }

    function _getCollateralLockerBalance() internal view returns (uint256) {
        return collateralAsset.balanceOf(collateralLocker);
    }

    function _getFundingLockerBalance() internal view returns (uint256) {
        return loanAsset.balanceOf(fundingLocker);
    }
}
