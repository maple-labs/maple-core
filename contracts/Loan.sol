// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "openzeppelin-contracts/utils/Pausable.sol";
import "openzeppelin-contracts/token/ERC20/SafeERC20.sol";

import "./interfaces/ICollateralLocker.sol";
import "./interfaces/ICollateralLockerFactory.sol";
import "./interfaces/IERC20Details.sol";
import "./interfaces/IFundingLocker.sol";
import "./interfaces/IFundingLockerFactory.sol";
import "./interfaces/IMapleGlobals.sol";
import "./interfaces/ILateFeeCalc.sol";
import "./interfaces/ILiquidityLocker.sol";
import "./interfaces/ILoanFactory.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IPoolFactory.sol";
import "./interfaces/IPremiumCalc.sol";
import "./interfaces/IRepaymentCalc.sol";
import "./interfaces/IUniswapRouter.sol";

import "./library/Util.sol";
import "./library/LoanLib.sol";

import "./token/LoanFDT.sol";

/// @title Loan maintains all accounting and functionality related to Loans.
contract Loan is LoanFDT, Pausable {

    using SafeMathInt     for int256;
    using SignedSafeMath  for int256;
    using SafeMath        for uint256;
    using SafeERC20       for IERC20;

    /**
        Ready      = The Loan has been initialized and is ready for funding (assuming funding period hasn't ended)
        Active     = The Loan has been drawdown and the Borrower is making payments
        Matured    = The Loan is fully paid off and has "matured"
        Expired    = The Loan did not initiate, and all funding was returned to Lenders
        Liquidated = The Loan has been liquidated
    */
    enum State { Ready, Active, Matured, Expired, Liquidated }

    State public loanState;  // The current state of this Loan, as defined in the State enum below.

    IERC20 public immutable liquidityAsset;      // The asset deposited by Lenders into the FundingLocker, when funding this Loan.
    IERC20 public immutable collateralAsset;     // The asset deposited by Borrower into the CollateralLocker, for collateralizing this Loan.

    address public immutable fundingLocker;      // The FundingLocker that holds custody of Loan funds before drawdown.
    address public immutable flFactory;          // The FundingLockerFactory.
    address public immutable collateralLocker;   // The CollateralLocker that holds custody of Loan collateral.
    address public immutable clFactory;          // The CollateralLockerFactory.
    address public immutable borrower;           // The Borrower of this Loan, responsible for repayments.
    address public immutable repaymentCalc;      // The RepaymentCalc for this Loan.
    address public immutable lateFeeCalc;        // The LateFeeCalc for this Loan.
    address public immutable premiumCalc;        // The PremiumCalc for this Loan.
    address public immutable superFactory;       // The LoanFactory that deployed this Loan.

    mapping(address => bool) public loanAdmins;  // Admin addresses that have permission to do certain operations in case of disaster management.

    uint256 public nextPaymentDue;  // The unix timestamp due date of the next payment.

    // Loan specifications
    uint256 public immutable apr;                     // The APR in basis points.
    uint256 public           paymentsRemaining;       // The number of payments remaining on the Loan.
    uint256 public immutable termDays;                // The total length of the Loan term in days.
    uint256 public immutable paymentIntervalSeconds;  // The time between Loan payments in seconds.
    uint256 public immutable requestAmount;           // The total requested amount for Loan.
    uint256 public immutable collateralRatio;         // The percentage of value of the drawdown amount to post as collateral in basis points.
    uint256 public immutable createdAt;               // The timestamp of when Loan was instantiated.
    uint256 public immutable fundingPeriod;           // The time for a Loan to be funded in seconds.
    uint256 public immutable defaultGracePeriod;      // The time a Borrower has, after a payment is due, to make a payment before a liquidation can occur.

    // Accounting variables
    uint256 public principalOwed;   // The amount of principal owed (initially the drawdown amount).
    uint256 public principalPaid;   // The amount of principal that has  been paid     by the Borrower since the Loan instantiation.
    uint256 public interestPaid;    // The amount of interest  that has  been paid     by the Borrower since the Loan instantiation.
    uint256 public feePaid;         // The amount of fees      that have been paid     by the Borrower since the Loan instantiation.
    uint256 public excessReturned;  // The amount of excess    that has  been returned to the Lenders  after the Loan drawdown.

    // Liquidation variables
    uint256 public amountLiquidated;   // The amount of Collateral Asset that has been liquidated after default.
    uint256 public amountRecovered;    // The amount of Liquidity Asset  that has been recovered  after default.
    uint256 public defaultSuffered;    // The difference between `amountRecovered` and `principalOwed` after liquidation.
    uint256 public liquidationExcess;  // If `amountRecovered > principalOwed`, this is the amount of Liquidity Asset that is to be returned to the Borrower.

    event       LoanFunded(address indexed fundedBy, uint256 amountFunded);
    event   BalanceUpdated(address indexed account, address indexed token, uint256 balance);
    event         Drawdown(uint256 drawdownAmount);
    event LoanStateChanged(State state);
    event     LoanAdminSet(address indexed loanAdmin, bool allowed);
    
    event PaymentMade(
        uint256 totalPaid,
        uint256 principalPaid,
        uint256 interestPaid,
        uint256 paymentsRemaining,
        uint256 principalOwed,
        uint256 nextPaymentDue,
        bool latePayment
    );
    
    event Liquidation(
        uint256 collateralSwapped,
        uint256 liquidityAssetReturned,
        uint256 liquidationExcess,
        uint256 defaultSuffered
    );

    /**
        @dev    Constructor for a Loan.
        @dev    It emits a `LoanStateChanged` event.
        @param  _borrower        Will receive the funding when calling `drawdown()`. Is also responsible for repayments.
        @param  _liquidityAsset  The asset the Borrower is requesting funding in.
        @param  _collateralAsset The asset provided as collateral by the Borrower.
        @param  _flFactory       Factory to instantiate FundingLocker with.
        @param  _clFactory       Factory to instantiate CollateralLocker with.
        @param  specs            Contains specifications for this Loan.
                                     specs[0] = apr
                                     specs[1] = termDays
                                     specs[2] = paymentIntervalDays (aka PID)
                                     specs[3] = requestAmount
                                     specs[4] = collateralRatio
        @param  calcs            The calculators used for this Loan.
                                     calcs[0] = repaymentCalc
                                     calcs[1] = lateFeeCalc
                                     calcs[2] = premiumCalc
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

    /**
        @dev   Draws down funding from FundingLocker, posts collateral, and transitions the Loan state from `Ready` to `Active`. Only the Borrower can call this function.
        @dev   It emits four `BalanceUpdated` events.
        @dev   It emits a `LoanStateChanged` event.
        @dev   It emits a `Drawdown` event.
        @param amt Amount of Liquidity Asset the Borrower draws down. Remainder is returned to the Loan where it can be claimed back by LoanFDT holders.
    */
    function drawdown(uint256 amt) external {
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

    /**
        @dev Makes a payment for this Loan. Amounts are calculated for the Borrower.
    */
    function makePayment() external {
        _whenProtocolNotPaused();
        _isValidState(State.Active);
        (uint256 total, uint256 principal, uint256 interest,, bool paymentLate) = getNextPayment();
        --paymentsRemaining;
        _makePayment(total, principal, interest, paymentLate);
    }

    /**
        @dev Makes the full payment for this Loan (a.k.a. "calling" the Loan). This requires the Borrower to pay a premium fee.
    */
    function makeFullPayment() external {
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

    /**
        @dev   Funds this Loan and mints LoanFDTs for `mintTo` (DebtLocker in the case of Pool funding).
               Only LiquidityLocker using valid/approved Pool can call this function.
        @dev   It emits a `LoanFunded` event.
        @dev   It emits a `BalanceUpdated` event.
        @param amt    Amount to fund the Loan.
        @param mintTo Address that LoanFDTs are minted to.
    */
    function fundLoan(address mintTo, uint256 amt) whenNotPaused external {
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

    /**
        @dev Handles returning capital to the Loan, where it can be claimed back by LoanFDT holders,
             if the Borrower has not drawn down on the Loan past the drawdown grace period.
        @dev It emits a `LoanStateChanged` event.
    */
    function unwind() external {
        _whenProtocolNotPaused();
        _isValidState(State.Ready);

        // Update accounting for `claim()` and transfer funds from FundingLocker to Loan.
        excessReturned = LoanLib.unwind(liquidityAsset, fundingLocker, createdAt, fundingPeriod);

        updateFundsReceived();

        // Transition state to `Expired`.
        loanState = State.Expired;
        emit LoanStateChanged(State.Expired);
    }

    /**
        @dev Triggers a default if the Loan meets certain default conditions, liquidating all collateral and updating accounting.
             Only the an account with sufficient LoanFDTs of this Loan can call this function.
        @dev It emits a `BalanceUpdated` event.
        @dev It emits a `Liquidation` event.
        @dev It emits a `LoanStateChanged` event.
    */
    function triggerDefault() external {
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

        emit Liquidation(
            amountLiquidated,  // Amount of Collateral Asset swapped.
            amountRecovered,   // Amount of Liquidity Asset recovered from swap.
            liquidationExcess, // Amount of Liquidity Asset returned to borrower.
            defaultSuffered    // Remaining losses after the liquidation.
        );
        emit LoanStateChanged(State.Liquidated);
    }

    /***********************/
    /*** Admin Functions ***/
    /***********************/

    /**
        @dev Triggers paused state. Halts functionality for certain functions. Only the Borrower or a Loan Admin can call this function.
    */
    function pause() external {
        _isValidBorrowerOrLoanAdmin();
        super._pause();
    }

    /**
        @dev Triggers unpaused state. Restores functionality for certain functions. Only the Borrower or a Loan Admin can call this function.
    */
    function unpause() external {
        _isValidBorrowerOrLoanAdmin();
        super._unpause();
    }

    /**
        @dev   Sets a Loan Admin. Only the Borrower can call this function.
        @dev   It emits a `LoanAdminSet` event.
        @param loanAdmin An address being allowed or disallowed as a Loan Admin.
        @param allowed   Status of a Loan Admin.
    */
    function setLoanAdmin(address loanAdmin, bool allowed) external {
        _whenProtocolNotPaused();
        _isValidBorrower();
        loanAdmins[loanAdmin] = allowed;
        emit LoanAdminSet(loanAdmin, allowed);
    }

    /**************************/
    /*** Governor Functions ***/
    /**************************/

    /**
        @dev   Transfers any locked funds to the Governor. Only the Governor can call this function.
        @param token Address of the token to be reclaimed.
    */
    function reclaimERC20(address token) external {
        LoanLib.reclaimERC20(token, address(liquidityAsset), _globals(superFactory));
    }

    /*********************/
    /*** FDT Functions ***/
    /*********************/

    /**
        @dev Withdraws all available funds earned through LoanFDT for a token holder.
        @dev It emits a `BalanceUpdated` event.
    */
    function withdrawFunds() public override {
        _whenProtocolNotPaused();
        super.withdrawFunds();
        emit BalanceUpdated(address(this), address(fundsToken), fundsToken.balanceOf(address(this)));
    }

    /************************/
    /*** Getter Functions ***/
    /************************/

    /**
        @dev    Returns the expected amount of Liquidity Asset to be recovered from a liquidation based on current oracle prices.
        @return The minimum amount of Liquidity Asset that can be expected by swapping Collateral Asset.
    */
    function getExpectedAmountRecovered() external view returns (uint256) {
        uint256 liquidationAmt = _getCollateralLockerBalance();
        return Util.calcMinAmount(_globals(superFactory), address(collateralAsset), address(liquidityAsset), liquidationAmt);
    }

    /**
        @dev    Returns information of the next payment amount.
        @return [0] = Entitled interest of the next payment (Principal + Interest only when the next payment is last payment of the Loan)
                [1] = Entitled principal amount needed to be paid in the next payment
                [2] = Entitled interest amount needed to be paid in the next payment
                [3] = Payment Due Date
                [4] = Is Payment Late
    */
    function getNextPayment() public view returns (uint256, uint256, uint256, uint256, bool) {
        return LoanLib.getNextPayment(repaymentCalc, nextPaymentDue, lateFeeCalc);
    }

    /**
        @dev    Returns the information of a full payment amount.
        @return total     Principal and interest owed, combined.
        @return principal Principal owed.
        @return interest  Interest owed.
    */
    function getFullPayment() public view returns (uint256 total, uint256 principal, uint256 interest) {
        (total, principal, interest) = LoanLib.getFullPayment(repaymentCalc, nextPaymentDue, lateFeeCalc, premiumCalc);
    }

    /**
        @dev    Calculates the collateral required to draw down amount.
        @param  amt The amount of the Liquidity Asset to draw down from the FundingLocker.
        @return The amount of the Collateral Asset required to post in the CollateralLocker for a given drawdown amount.
    */
    function collateralRequiredForDrawdown(uint256 amt) public view returns (uint256) {
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
