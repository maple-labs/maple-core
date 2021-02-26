// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

import "./interfaces/ICollateralLocker.sol";
import "./interfaces/ICollateralLockerFactory.sol";
import "./interfaces/IERC20Details.sol";
import "./interfaces/IFundingLocker.sol";
import "./interfaces/IFundingLockerFactory.sol";
import "./interfaces/IGlobals.sol";
import "./interfaces/ILateFeeCalc.sol";
import "./interfaces/ILoanFactory.sol";
import "./interfaces/IPremiumCalc.sol";
import "./interfaces/IRepaymentCalc.sol";
import "./interfaces/IUniswapRouter.sol";
import "./library/Util.sol";
import "./library/LoanLib.sol";

import "./token/FDT.sol";

import "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";

/// @title Loan is the core loan vault contract.
contract Loan is FDT, Pausable {
    
    using SafeMathInt     for int256;
    using SignedSafeMath  for int256;
    using SafeMath        for uint256;

    /**
        Live       = The loan has been initialized and is open for funding (assuming funding period not ended).
        Active     = The loan has been drawdown and the borrower is making payments.
        Matured    = The loan is fully paid off and has "matured".
        Expired    = The loan did not initiate, and all funding was returned to lenders.
        Liquidated = The loan has been liquidated.
    */
    enum State { Live, Active, Matured, Expired, Liquidated }

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

    mapping(address => bool) public admins;  // Admin addresses that have permission to do certain operations in case of disaster mgt.

    uint256 public principalOwed;   // The principal owed (initially the drawdown amount).
    uint256 public drawdownAmount;  // The amount the borrower drew down, historical reference for calculators.
    uint256 public nextPaymentDue;  // The unix timestamp due date of next payment.

    // Loan specifications
    uint256 public apr;         
    uint256 public paymentsRemaining;
    uint256 public termDays;
    uint256 public paymentIntervalSeconds; 
    uint256 public requestAmount;
    uint256 public collateralRatio;
    uint256 public fundingPeriodSeconds;
    uint256 public createdAt;

    // Accounting variables
    uint256 public principalPaid;
    uint256 public interestPaid;
    uint256 public feePaid;
    uint256 public excessReturned;
    
    // Liquidation variables
    uint256 public amountLiquidated;
    uint256 public amountRecovered;
    uint256 public defaultSuffered;
    uint256 public liquidationExcess;

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
                specs[3] = requestAmount
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
        requestAmount          = specs[3];
        collateralRatio        = specs[4];
        fundingPeriodSeconds   = specs[5].mul(1 days);
        repaymentCalc          = calcs[0];
        lateFeeCalc            = calcs[1];
        premiumCalc            = calcs[2];
        nextPaymentDue         = block.timestamp.add(paymentIntervalSeconds);
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
    function fundLoan(address mintTo, uint256 amt) whenNotPaused external {
        _whenProtocolNotPaused();
        _isValidState(State.Live);
        _checkValidTransferFrom(loanAsset.transferFrom(msg.sender, fundingLocker, amt));

        uint256 wad = _toWad(amt);  // Convert to WAD precision
        _mint(mintTo, wad);         // Mint FDT to `mintTo` i.e Debt locker contract.

        emit LoanFunded(amt, mintTo);
        _emitBalanceUpdateEventForFundingLocker();
    }

    /**
        @dev If the borrower has not drawn down loan past grace period, return capital to lenders.
    */
    function unwind() external {
        _whenProtocolNotPaused();
        _isValidState(State.Live);

        // Update accounting for claim()
        excessReturned += LoanLib.unwind(loanAsset, superFactory, fundingLocker, createdAt);

        // Transition state to Expired.
        loanState = State.Expired;
    }

    /**
        @dev Drawdown funding from FundingLocker, post collateral, and transition loanState from Funding to Active.
        @param  amt Amount of loanAsset borrower draws down, remainder is returned to Loan.
    */
    function drawdown(uint256 amt) external {
        _whenProtocolNotPaused();
        _isValidBorrower();
        _isValidState(State.Live);
        IGlobals globals = _globals(superFactory);

        IFundingLocker _fundingLocker = IFundingLocker(fundingLocker);

        require(amt >= requestAmount,               "Loan:AMT_LT_MIN_RAISE");
        require(amt <= _getFundingLockerBalance(),  "Loan:AMT_GT_FUNDED_AMT");

        // Update the principal owed and drawdown amount for this loan.
        principalOwed  = amt;
        drawdownAmount = amt;

        loanState = State.Active;

        // Transfer the required amount of collateral for drawdown from Borrower to CollateralLocker.
        _checkValidTransferFrom(collateralAsset.transferFrom(borrower, collateralLocker, collateralRequiredForDrawdown(amt)));

        // Transfer funding amount from FundingLocker to Borrower, then drain remaining funds to Loan.
        uint treasuryFee = globals.treasuryFee();
        uint investorFee = globals.investorFee();

        address treasury = globals.mapleTreasury();

        // Update investorFee locally.
        feePaid             = amt.mul(investorFee).div(10000);
        uint256 treasuryAmt = amt.mul(treasuryFee).div(10000);  // Calculate amt to send to MapleTreasury

        // TODO: Change name from transferFee
        _transferFee(_fundingLocker, treasury,      treasuryAmt);                        // Send treasuryFee directly to MapleTreasury.
        _transferFee(_fundingLocker, address(this), feePaid);                            // Transfer `feePaid` to the this i.e loan contract.
        _transferFee(_fundingLocker, borrower,      amt.sub(treasuryAmt).sub(feePaid));  // Transfer drawdown amount to Borrower.

        // Update excessReturned locally.
        excessReturned = _getFundingLockerBalance();

        // Drain remaining funds from FundingLocker.
        require(_fundingLocker.drain(), "Loan:DRAIN");

        _emitBalanceUpdateEventForCollateralLocker();
        _emitBalanceUpdateEventForFundingLocker();
        _emitBalanceUpdateEventForLoan();

        emit BalanceUpdated(treasury, address(loanAsset), loanAsset.balanceOf(treasury));
        
        emit Drawdown(amt);
    }

    /**
        @dev Public getter to know how much minimum amount of loan asset will get by swapping collateral asset.
     */
    function getExpectedAmountRecovered() public view returns(uint256) {
        uint256 liquidationAmt = _getCollateralLockerBalance();
        return Util.calcMinAmount(_globals(superFactory), address(collateralAsset), address(loanAsset), liquidationAmt);
    }

    /**
        @dev Triggers default flow for loan, liquidating all collateral and updating accounting.
    */
    function _triggerDefault() internal {

        (amountLiquidated, amountRecovered) = LoanLib.triggerDefault(collateralAsset, _getCollateralLockerBalance(), address(loanAsset), superFactory, collateralLocker);

        // Reduce principal owed by amount received (as much as is required for principal owed == 0).
        if (amountRecovered > principalOwed) {
            liquidationExcess = amountRecovered.sub(principalOwed);
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
            amountLiquidated,  // Amount of collateralAsset swapped
            amountRecovered,   // Amount of loanAsset recovered from swap
            liquidationExcess, // Amount of loanAsset returned to borrower
            defaultSuffered    // Remaining losses after liquidation
        );

    }

    /**
        @dev Trigger a default. Does nothing if block.timestamp <= nextPaymentDue + gracePeriod.
    */
    // TODO: Talk with auditors about having a switch for this function
    function triggerDefault() external {
        _whenProtocolNotPaused();
        _isValidState(State.Active);
        require(LoanLib.hasDefaultTriggered(nextPaymentDue, superFactory, balanceOf(msg.sender)), "Loan:FAILED_TO_LIQUIDATE");
        _triggerDefault();
    }

    /**
        @dev Returns information on next payment amount.
        @return [0] = Principal + Interest
                [1] = Principal 
                [2] = Interest
                [3] = Payment Due Date
    */
    function getNextPayment() public view returns(uint256, uint256, uint256, uint256) {
        return LoanLib.getNextPayment(superFactory, repaymentCalc, nextPaymentDue, lateFeeCalc);
    }

    /**
        @dev Make the next payment for this loan.
    */
    function makePayment() external {
        _whenProtocolNotPaused();
        _isValidState(State.Active);
        (uint256 total, uint256 principal, uint256 interest,) = getNextPayment();
        paymentsRemaining--;
        _makePayment(total, principal, interest);
    }

    /**
        @dev Make the full payment for this loan, a.k.a. "calling" the loan.
    */
    function makeFullPayment() public {
        _whenProtocolNotPaused();
        _isValidState(State.Active);
        (uint256 total, uint256 principal, uint256 interest) = getFullPayment();
        paymentsRemaining = uint256(0);
        _makePayment(total, principal, interest);
    }

    /**
        @dev Internal function to update the payment details.
     */
    function _makePayment(uint256 total, uint256 principal, uint256 interest) internal {

        _checkValidTransferFrom(loanAsset.transferFrom(msg.sender, address(this), total));

        // Caching it to reduce the `SLOADS`.
        uint256 _paymentRemaining = paymentsRemaining;
         // Update internal accounting variables.
        if (_paymentRemaining == uint256(0)) {
            principalOwed  = 0;
        } else {
            principalOwed  = principalOwed.sub(principal);
            nextPaymentDue = nextPaymentDue.add(paymentIntervalSeconds);
        }
        principalPaid  = principalPaid.add(principal);
        interestPaid   = interestPaid.add(interest);

        updateFundsReceived();

        emit PaymentMade(
            total, 
            principal, 
            interest, 
            _paymentRemaining, 
            principalOwed, 
            _paymentRemaining > 0 ? nextPaymentDue : 0, 
            false
        );

        // Handle final payment.
        if (_paymentRemaining == 0) {
            loanState = State.Matured;
            nextPaymentDue = 0;
            // Transferring all collaterised funds back to the borrower.
            require(ICollateralLocker(collateralLocker).pull(borrower, _getCollateralLockerBalance()), "Loan:COLLATERAL_PULL");
            _emitBalanceUpdateEventForCollateralLocker();
        }
        _emitBalanceUpdateEventForLoan();
    }

    /**
        @dev Returns information on full payment amount.
        @return total Principal and interest owed, combined.
        @return principal Principal owed.
        @return interest Interest owed.
    */
    function getFullPayment() public view returns(uint256 total, uint256 principal, uint256 interest) {
        (total, principal, interest) = IPremiumCalc(premiumCalc).getPremiumPayment(address(this));
    }

    /**
        @dev Helper for calculating collateral required to drawdown amt.
        @param  amt The amount of loanAsset to drawdown from FundingLocker.
        @return The amount of collateralAsset required to post in CollateralLocker for given drawdown amt.
    */
    function collateralRequiredForDrawdown(uint256 amt) public view returns(uint256) {
        return LoanLib.collateralRequiredForDrawdown(collateralAsset, loanAsset, collateralRatio, superFactory, amt);
    }

    /**
     * @dev Withdraws all available funds for a token holder
     */
    function withdrawFunds() public override {
        _whenProtocolNotPaused();
        super.withdrawFunds();
    }

    /**
        @dev Triggers stopped state.
             The contract must not be paused.
    */
    function pause() external { 
        _isValidBorrowerOrAdmin();
        super._pause();
    }

    /**
        @dev Returns to normal state.
             The contract must be paused.
    */
    function unpause() external {
        _isValidBorrowerOrAdmin();
        super._unpause();
    }

    /**
      @dev Set admin
      @param newAdmin new admin address.
      @param allowed Status of an admin.
     */
    function setAdmin(address newAdmin, bool allowed) external {
        _isValidBorrower();
        admins[newAdmin] = allowed;
    }

    function _whenProtocolNotPaused() internal {
        require(!_globals(superFactory).protocolPaused(), "Loan:PROTOCOL_PAUSED");
    }

    function _isValidBorrowerOrAdmin() internal {
        require(msg.sender == borrower || admins[msg.sender], "Pool:UNAUTHORIZED");
    }

    function _toWad(uint256 amt) internal view returns(uint256) {
        return amt.mul(10 ** 18).div(10 ** loanAsset.decimals());
    }

    function _checkValidTransferFrom(bool isValid) internal pure {
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

    function _isValidState(State _state) internal view {	
        require(loanState == _state, "Loan:INVALID_STATE");	
    }	

    function _isValidBorrower() internal view {	
        require(msg.sender == borrower, "Loan:INVALID_BORROWER");	
    }

    function _transferFee(IFundingLocker from, address to, uint256 value) internal {
        require(from.pull(to, value), "Loan:FAILED_TO_TRANSFER_FEE");
    }

    function _emitBalanceUpdateEventForLoan() internal {
        emit BalanceUpdated(address(this), address(loanAsset), loanAsset.balanceOf(address(this)));
    }

    function _emitBalanceUpdateEventForFundingLocker() internal {
        emit BalanceUpdated(fundingLocker, address(loanAsset), _getFundingLockerBalance());
    }

    function _emitBalanceUpdateEventForCollateralLocker() internal {
        emit BalanceUpdated(collateralLocker, address(collateralAsset), _getCollateralLockerBalance());
    }
}
