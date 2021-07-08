// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/SafeERC20.sol";
import "../../../../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";

import "../../../external-interfaces/IERC20Details.sol";

import "libraries/loan/v1/LoanLib.sol";
import "libraries/util/v1/Util.sol";

import "../../collateral-locker/v1/interfaces/ICollateralLocker.sol";
import "../../collateral-locker/v1/interfaces/ICollateralLockerFactory.sol";
import "../../funding-locker/v1/interfaces/IFundingLocker.sol";
import "../../funding-locker/v1/interfaces/IFundingLockerFactory.sol";
import "../..//globals/v1/interfaces/IMapleGlobals.sol";
import "../../late-fee-calculator/v1/interfaces/ILateFeeCalc.sol";
import "../../liquidity-locker/v1/interfaces/ILiquidityLocker.sol";
import "../../pool/v1/interfaces/IPool.sol";
import "../../pool/v1/interfaces/IPoolFactory.sol";

import "./interfaces/ILoan.sol";
import "./interfaces/ILoanFactory.sol";

import "./LoanFDT.sol";

/// @title Loan maintains all accounting and functionality related to Loans.
contract Loan is ILoan, LoanFDT, Pausable {

    using SafeMathInt     for int256;
    using SignedSafeMath  for int256;
    using SafeMath        for uint256;
    using SafeERC20       for IERC20;

    State public override loanState;

    IERC20 public override immutable liquidityAsset;
    IERC20 public override immutable collateralAsset;

    address public override immutable fundingLocker;
    address public override immutable flFactory;
    address public override immutable collateralLocker;
    address public override immutable clFactory;
    address public override immutable borrower;
    address public override immutable repaymentCalc;
    address public override immutable lateFeeCalc;
    address public override immutable premiumCalc;
    address public override immutable superFactory;

    mapping(address => bool) public override loanAdmins;

    uint256 public override nextPaymentDue;

    // Loan specifications
    uint256 public override immutable apr;
    uint256 public override           paymentsRemaining;
    uint256 public override immutable termDays;
    uint256 public override immutable paymentIntervalSeconds;
    uint256 public override immutable requestAmount;
    uint256 public override immutable collateralRatio;
    uint256 public override immutable createdAt;
    uint256 public override immutable fundingPeriod;
    uint256 public override immutable defaultGracePeriod;

    // Accounting variables
    uint256 public override principalOwed;
    uint256 public override principalPaid;
    uint256 public override interestPaid;
    uint256 public override feePaid;
    uint256 public override excessReturned;

    // Liquidation variables
    uint256 public override amountLiquidated;
    uint256 public override amountRecovered;
    uint256 public override defaultSuffered;
    uint256 public override liquidationExcess;

    /**
        @dev    Constructor for a Loan. 
        @dev    It emits a `LoanStateChanged` event. 
        @param  _borrower        Will receive the funding when calling `drawdown()`. Is also responsible for repayments.
        @param  _liquidityAsset  The asset the Borrower is requesting funding in.
        @param  _collateralAsset The asset provided as collateral by the Borrower.
        @param  _flFactory       Factory to instantiate FundingLocker with.
        @param  _clFactory       Factory to instantiate CollateralLocker with.
        @param  specs            Contains specifications for this Loan. 
                                     [0] => apr, 
                                     [1] => termDays, 
                                     [2] => paymentIntervalDays (aka PID), 
                                     [3] => requestAmount, 
                                     [4] => collateralRatio. 
        @param  calcs            The calculators used for this Loan. 
                                     [0] => repaymentCalc, 
                                     [1] => lateFeeCalc, 
                                     [2] => premiumCalc. 
     */
    constructor(
        address _borrower,
        address _liquidityAsset,
        address _collateralAsset,
        address _flFactory,
        address _clFactory,
        uint256[5] memory specs,
        address[3] memory calcs
    ) LoanFDT("Maple Loan Token", "MPL-LOAN", _liquidityAsset) public {
        IMapleGlobals globals = _globals(msg.sender);

        // Perform validity cross-checks.
        LoanLib.loanSanityChecks(globals, _liquidityAsset, _collateralAsset, specs);

        borrower        = _borrower;
        liquidityAsset  = IERC20(_liquidityAsset);
        collateralAsset = IERC20(_collateralAsset);
        flFactory       = _flFactory;
        clFactory       = _clFactory;
        createdAt       = block.timestamp;

        // Update state variables.
        apr                    = specs[0];
        termDays               = specs[1];
        paymentsRemaining      = specs[1].div(specs[2]);
        paymentIntervalSeconds = specs[2].mul(1 days);
        requestAmount          = specs[3];
        collateralRatio        = specs[4];
        fundingPeriod          = globals.fundingPeriod();
        defaultGracePeriod     = globals.defaultGracePeriod();
        repaymentCalc          = calcs[0];
        lateFeeCalc            = calcs[1];
        premiumCalc            = calcs[2];
        superFactory           = msg.sender;

        // Deploy lockers.
        collateralLocker = ICollateralLockerFactory(_clFactory).newLocker(_collateralAsset);
        fundingLocker    = IFundingLockerFactory(_flFactory).newLocker(_liquidityAsset);
        emit LoanStateChanged(State.Ready);
    }

    /**************************/
    /*** Borrower Functions ***/
    /**************************/

    function drawdown(uint256 amt) external override {
        _whenProtocolNotPaused();
        _isValidBorrower();
        _isValidState(State.Ready);
        IMapleGlobals globals = _globals(superFactory);

        IFundingLocker _fundingLocker = IFundingLocker(fundingLocker);

        require(amt >= requestAmount,              "L:AMT_LT_REQUEST_AMT");
        require(amt <= _getFundingLockerBalance(), "L:AMT_GT_FUNDED_AMT");

        // Update accounting variables for the Loan.
        principalOwed  = amt;
        nextPaymentDue = block.timestamp.add(paymentIntervalSeconds);

        loanState = State.Active;

        // Transfer the required amount of collateral for drawdown from the Borrower to the CollateralLocker.
        collateralAsset.safeTransferFrom(borrower, collateralLocker, collateralRequiredForDrawdown(amt));

        // Transfer funding amount from the FundingLocker to the Borrower, then drain remaining funds to the Loan.
        uint256 treasuryFee = globals.treasuryFee();
        uint256 investorFee = globals.investorFee();

        address treasury = globals.mapleTreasury();

        uint256 _feePaid = feePaid = amt.mul(investorFee).div(10_000);  // Update fees paid for `claim()`.
        uint256 treasuryAmt        = amt.mul(treasuryFee).div(10_000);  // Calculate amount to send to the MapleTreasury.

        _transferFunds(_fundingLocker, treasury, treasuryAmt);                         // Send the treasury fee directly to the MapleTreasury.
        _transferFunds(_fundingLocker, borrower, amt.sub(treasuryAmt).sub(_feePaid));  // Transfer drawdown amount to the Borrower.

        // Update excessReturned for `claim()`.
        excessReturned = _getFundingLockerBalance().sub(_feePaid);

        // Drain remaining funds from the FundingLocker (amount equal to `excessReturned` plus `feePaid`)
        _fundingLocker.drain();

        // Call `updateFundsReceived()` update LoanFDT accounting with funds received from fees and excess returned.
        updateFundsReceived();

        _emitBalanceUpdateEventForCollateralLocker();
        _emitBalanceUpdateEventForFundingLocker();
        _emitBalanceUpdateEventForLoan();

        emit BalanceUpdated(treasury, address(liquidityAsset), liquidityAsset.balanceOf(treasury));
        emit LoanStateChanged(State.Active);
        emit Drawdown(amt);
    }

    function makePayment() external override {
        _whenProtocolNotPaused();
        _isValidState(State.Active);
        (uint256 total, uint256 principal, uint256 interest,, bool paymentLate) = getNextPayment();
        --paymentsRemaining;
        _makePayment(total, principal, interest, paymentLate);
    }

    function makeFullPayment() external override {
        _whenProtocolNotPaused();
        _isValidState(State.Active);
        (uint256 total, uint256 principal, uint256 interest) = getFullPayment();
        paymentsRemaining = uint256(0);
        _makePayment(total, principal, interest, false);
    }

    /**
        @dev Updates the payment variables and transfers funds from the Borrower into the Loan.
        @dev It emits one or two `BalanceUpdated` events (depending if payments remaining).
        @dev It emits a `LoanStateChanged` event if no payments remaining.
        @dev It emits a `PaymentMade` event.
    */
    function _makePayment(uint256 total, uint256 principal, uint256 interest, bool paymentLate) internal {

        // Caching to reduce `SLOADs`.
        uint256 _paymentsRemaining = paymentsRemaining;

        // Update internal accounting variables.
        interestPaid = interestPaid.add(interest);
        if (principal > uint256(0)) principalPaid = principalPaid.add(principal);

        if (_paymentsRemaining > uint256(0)) {
            // Update info related to next payment and, if needed, decrement principalOwed.
            nextPaymentDue = nextPaymentDue.add(paymentIntervalSeconds);
            if (principal > uint256(0)) principalOwed = principalOwed.sub(principal);
        } else {
            // Update info to close loan.
            principalOwed  = uint256(0);
            loanState      = State.Matured;
            nextPaymentDue = uint256(0);

            // Transfer all collateral back to the Borrower.
            ICollateralLocker(collateralLocker).pull(borrower, _getCollateralLockerBalance());
            _emitBalanceUpdateEventForCollateralLocker();
            emit LoanStateChanged(State.Matured);
        }

        // Loan payer sends funds to the Loan.
        liquidityAsset.safeTransferFrom(msg.sender, address(this), total);

        // Update FDT accounting with funds received from interest payment.
        updateFundsReceived();

        emit PaymentMade(
            total,
            principal,
            interest,
            _paymentsRemaining,
            principalOwed,
            _paymentsRemaining > 0 ? nextPaymentDue : 0,
            paymentLate
        );

        _emitBalanceUpdateEventForLoan();
    }

    /************************/
    /*** Lender Functions ***/
    /************************/

    function fundLoan(address mintTo, uint256 amt) whenNotPaused external override {
        _whenProtocolNotPaused();
        _isValidState(State.Ready);
        _isValidPool();
        _isWithinFundingPeriod();
        liquidityAsset.safeTransferFrom(msg.sender, fundingLocker, amt);

        uint256 wad = _toWad(amt);  // Convert to WAD precision.
        _mint(mintTo, wad);         // Mint LoanFDTs to `mintTo` (i.e DebtLocker contract).

        emit LoanFunded(mintTo, amt);
        _emitBalanceUpdateEventForFundingLocker();
    }

    function unwind() external override {
        _whenProtocolNotPaused();
        _isValidState(State.Ready);

        // Update accounting for `claim()` and transfer funds from FundingLocker to Loan.
        excessReturned = LoanLib.unwind(liquidityAsset, fundingLocker, createdAt, fundingPeriod);

        updateFundsReceived();

        // Transition state to `Expired`.
        loanState = State.Expired;
        emit LoanStateChanged(State.Expired);
    }

    function triggerDefault() external override {
        _whenProtocolNotPaused();
        _isValidState(State.Active);
        require(LoanLib.canTriggerDefault(nextPaymentDue, defaultGracePeriod, superFactory, balanceOf(msg.sender), totalSupply()), "L:FAILED_TO_LIQ");

        // Pull the Collateral Asset from the CollateralLocker, swap to the Liquidity Asset, and hold custody of the resulting Liquidity Asset in the Loan.
        (amountLiquidated, amountRecovered) = LoanLib.liquidateCollateral(collateralAsset, address(liquidityAsset), superFactory, collateralLocker);
        _emitBalanceUpdateEventForCollateralLocker();

        // Decrement `principalOwed` by `amountRecovered`, set `defaultSuffered` to the difference (shortfall from the liquidation).
        if (amountRecovered <= principalOwed) {
            principalOwed   = principalOwed.sub(amountRecovered);
            defaultSuffered = principalOwed;
        }
        // Set `principalOwed` to zero and return excess value from the liquidation back to the Borrower.
        else {
            liquidationExcess = amountRecovered.sub(principalOwed);
            principalOwed = 0;
            liquidityAsset.safeTransfer(borrower, liquidationExcess);  // Send excess to the Borrower.
        }

        // Update LoanFDT accounting with funds received from the liquidation.
        updateFundsReceived();

        // Transition `loanState` to `Liquidated`
        loanState = State.Liquidated;

        emit Liquidation(amountLiquidated, amountRecovered, liquidationExcess, defaultSuffered);
        emit LoanStateChanged(State.Liquidated);
    }

    /***********************/
    /*** Admin Functions ***/
    /***********************/

    function pause() external override {
        _isValidBorrowerOrLoanAdmin();
        super._pause();
    }

    function unpause() external override {
        _isValidBorrowerOrLoanAdmin();
        super._unpause();
    }

    function setLoanAdmin(address loanAdmin, bool allowed) external override {
        _whenProtocolNotPaused();
        _isValidBorrower();
        loanAdmins[loanAdmin] = allowed;
        emit LoanAdminSet(loanAdmin, allowed);
    }

    /**************************/
    /*** Governor Functions ***/
    /**************************/

    function reclaimERC20(address token) external override {
        LoanLib.reclaimERC20(token, address(liquidityAsset), _globals(superFactory));
    }

    /*********************/
    /*** FDT Functions ***/
    /*********************/

    function withdrawFunds() public override(ILoan, LoanFDT) {
        _whenProtocolNotPaused();
        super.withdrawFunds();
        emit BalanceUpdated(address(this), address(fundsToken), fundsToken.balanceOf(address(this)));
    }

    /************************/
    /*** Getter Functions ***/
    /************************/

    function getExpectedAmountRecovered() external override view returns (uint256) {
        uint256 liquidationAmt = _getCollateralLockerBalance();
        return Util.calcMinAmount(_globals(superFactory), address(collateralAsset), address(liquidityAsset), liquidationAmt);
    }

    function getNextPayment() public override view returns (uint256, uint256, uint256, uint256, bool) {
        return LoanLib.getNextPayment(repaymentCalc, nextPaymentDue, lateFeeCalc);
    }

    function getFullPayment() public override view returns (uint256 total, uint256 principal, uint256 interest) {
        (total, principal, interest) = LoanLib.getFullPayment(repaymentCalc, nextPaymentDue, lateFeeCalc, premiumCalc);
    }

    function collateralRequiredForDrawdown(uint256 amt) public override view returns (uint256) {
        return LoanLib.collateralRequiredForDrawdown(
            IERC20Details(address(collateralAsset)),
            IERC20Details(address(liquidityAsset)),
            collateralRatio,
            superFactory,
            amt
        );
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    /**
        @dev Checks that the protocol is not in a paused state.
     */
    function _whenProtocolNotPaused() internal view {
        require(!_globals(superFactory).protocolPaused(), "L:PROTO_PAUSED");
    }

    /**
        @dev Checks that `msg.sender` is the Borrower or a Loan Admin.
     */
    function _isValidBorrowerOrLoanAdmin() internal view {
        require(msg.sender == borrower || loanAdmins[msg.sender], "L:NOT_BORROWER_OR_ADMIN");
    }

    /**
        @dev Converts to WAD precision.
     */
    function _toWad(uint256 amt) internal view returns (uint256) {
        return amt.mul(10 ** 18).div(10 ** IERC20Details(address(liquidityAsset)).decimals());
    }

    /**
        @dev Returns the MapleGlobals instance.
     */
    function _globals(address loanFactory) internal view returns (IMapleGlobals) {
        return IMapleGlobals(ILoanFactory(loanFactory).globals());
    }

    /**
        @dev Returns the CollateralLocker balance.
     */
    function _getCollateralLockerBalance() internal view returns (uint256) {
        return collateralAsset.balanceOf(collateralLocker);
    }

    /**
        @dev Returns the FundingLocker balance.
     */
    function _getFundingLockerBalance() internal view returns (uint256) {
        return liquidityAsset.balanceOf(fundingLocker);
    }

    /**
        @dev   Checks that the current state of the Loan matches the provided state.
        @param _state Enum of desired Loan state.
     */
    function _isValidState(State _state) internal view {
        require(loanState == _state, "L:INVALID_STATE");
    }

    /**
        @dev Checks that `msg.sender` is the Borrower.
     */
    function _isValidBorrower() internal view {
        require(msg.sender == borrower, "L:NOT_BORROWER");
    }

    /**
        @dev Checks that `msg.sender` is a Lender (LiquidityLocker) that is using an approved Pool to fund the Loan.
     */
    function _isValidPool() internal view {
        address pool        = ILiquidityLocker(msg.sender).pool();
        address poolFactory = IPool(pool).superFactory();
        require(
            _globals(superFactory).isValidPoolFactory(poolFactory) &&
            IPoolFactory(poolFactory).isPool(pool),
            "L:INVALID_LENDER"
        );
    }

    /**
        @dev Checks that "now" is currently within the funding period.
     */
    function _isWithinFundingPeriod() internal view {
        require(block.timestamp <= createdAt.add(fundingPeriod), "L:PAST_FUNDING_PERIOD");
    }

    /**
        @dev   Transfers funds from the FundingLocker.
        @param from  Instance of the FundingLocker.
        @param to    Address to send funds to.
        @param value Amount to send.
     */
    function _transferFunds(IFundingLocker from, address to, uint256 value) internal {
        from.pull(to, value);
    }

    /**
        @dev Emits a `BalanceUpdated` event for the Loan.
        @dev It emits a `BalanceUpdated` event.
     */
    function _emitBalanceUpdateEventForLoan() internal {
        emit BalanceUpdated(address(this), address(liquidityAsset), liquidityAsset.balanceOf(address(this)));
    }

    /**
        @dev Emits a `BalanceUpdated` event for the FundingLocker.
        @dev It emits a `BalanceUpdated` event.
     */
    function _emitBalanceUpdateEventForFundingLocker() internal {
        emit BalanceUpdated(fundingLocker, address(liquidityAsset), _getFundingLockerBalance());
    }

    /**
        @dev Emits a `BalanceUpdated` event for the CollateralLocker.
        @dev It emits a `BalanceUpdated` event.
     */
    function _emitBalanceUpdateEventForCollateralLocker() internal {
        emit BalanceUpdated(collateralLocker, address(collateralAsset), _getCollateralLockerBalance());
    }

}
