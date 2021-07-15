// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { IERC20 } from "../../../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { IBasicFundsTokenFDT } from "../../../funds-distribution-token/v1/interfaces/IBasicFundsTokenFDT.sol";

interface ILoan is IBasicFundsTokenFDT {

    /**
        Ready      = The Loan has been initialized and is ready for funding (assuming funding period hasn't ended).
        Active     = The Loan has been drawdown and the Borrower is making payments.
        Matured    = The Loan is fully paid off and has "matured".
        Expired    = The Loan did not initiate, and all funding was returned to Lenders.
        Liquidated = The Loan has been liquidated.
     */
    enum State { Ready, Active, Matured, Expired, Liquidated }

    /**
        @dev   Emits an event indicating the Loan was funded.
        @param fundedBy     The Pool that funded the Loan.
        @param amountFunded The amount the Loan was funded for.
     */
    event LoanFunded(address indexed fundedBy, uint256 amountFunded);

    /**
        @dev   Emits an event indicating the balance for an account was updated.
        @param account The address of an account.
        @param token   The token address of the asset.
        @param balance The new balance of `token` for `account`.
     */
    event BalanceUpdated(address indexed account, address indexed token, uint256 balance);

    /**
        @dev   Emits an event indicating the some loaned amount was drawn down.
        @param drawdownAmount The amount that was drawn down.
     */
    event Drawdown(uint256 drawdownAmount);

    /**
        @dev   Emits an event indicating the state of the Loan changed.
        @param state The state of the Loan.
     */
    event LoanStateChanged(State state);

    /**
        @dev   Emits an event indicating the an Admin for the Loan was set.
        @param loanAdmin The address of some Loan Admin.
        @param allowed   Whether `loanAdmin` is a Loan Admin for this Loan.
     */
    event LoanAdminSet(address indexed loanAdmin, bool allowed);

    /**
        @dev   Emits an event indicating the a payment was made for the Loan.
        @param totalPaid         The total amount paid.
        @param principalPaid     The principal portion of the amount paid.
        @param interestPaid      The interest portion of the amount paid.
        @param paymentsRemaining The amount of payment remaining.
        @param principalOwed     The outstanding principal of the Loan.
        @param nextPaymentDue    The timestamp of the due date of the next payment.
        @param latePayment       Whether this payment was late.
     */
    event PaymentMade(
        uint256 totalPaid,
        uint256 principalPaid,
        uint256 interestPaid,
        uint256 paymentsRemaining,
        uint256 principalOwed,
        uint256 nextPaymentDue,
        bool latePayment
    );

    /**
        @dev   Emits an event indicating the the Loan was liquidated.
        @param collateralSwapped      The amount of Collateral Asset swapped.
        @param liquidityAssetReturned The amount of Liquidity Asset recovered from swap.
        @param liquidationExcess      The amount of Liquidity Asset returned to borrower.
        @param defaultSuffered        The remaining losses after the liquidation.
     */
    event Liquidation(
        uint256 collateralSwapped,
        uint256 liquidityAssetReturned,
        uint256 liquidationExcess,
        uint256 defaultSuffered
    );

    /**
        @dev The current state of this Loan, as defined in the State enum below.
     */
    function loanState() external view returns (State);

    /**
        @dev The asset deposited by Lenders into the FundingLocker, when funding this Loan.
     */
    function liquidityAsset() external view returns (IERC20);

    /**
        @dev The asset deposited by Borrower into the CollateralLocker, for collateralizing this Loan.
     */
    function collateralAsset() external view returns (IERC20);

    /**
        @dev The FundingLocker that holds custody of Loan funds before drawdown.
     */
    function fundingLocker() external view returns (address);

    /**
        @dev The FundingLockerFactory.
     */
    function flFactory() external view returns (address);

    /**
        @dev The CollateralLocker that holds custody of Loan collateral.
     */
    function collateralLocker() external view returns (address);

    /**
        @dev The CollateralLockerFactory.
     */
    function clFactory() external view returns (address);

    /**
        @dev The Borrower of this Loan, responsible for repayments.
     */
    function borrower() external view returns (address);

    /**
        @dev The RepaymentCalc for this Loan.
     */
    function repaymentCalc() external view returns (address);

    /**
        @dev The LateFeeCalc for this Loan.
     */
    function lateFeeCalc() external view returns (address);

    /**
        @dev The PremiumCalc for this Loan.
     */
    function premiumCalc() external view returns (address);

    /**
        @dev The LoanFactory that deployed this Loan.
     */
    function superFactory() external view returns (address);

    /**
        @param  loanAdmin The address of some admin.
        @return Whether the `loanAdmin` has permission to do certain operations in case of disaster management.
     */
    function loanAdmins(address loanAdmin) external view returns (bool);

    /**
        @dev The unix timestamp due date of the next payment.
     */
    function nextPaymentDue() external view returns (uint256);

    /**
        @dev The APR in basis points.
     */
    function apr() external view returns (uint256);

    /**
        @dev The number of payments remaining on the Loan.
     */
    function paymentsRemaining() external view returns (uint256);

    /**
        @dev The total length of the Loan term in days.
     */
    function termDays() external view returns (uint256);

    /**
        @dev The time between Loan payments in seconds.
     */
    function paymentIntervalSeconds() external view returns (uint256);

    /**
        @dev The total requested amount for Loan.
     */
    function requestAmount() external view returns (uint256);

    /**
        @dev The percentage of value of the drawdown amount to post as collateral in basis points.
     */
    function collateralRatio() external view returns (uint256);

    /**
        @dev The timestamp of when Loan was instantiated.
     */
    function createdAt() external view returns (uint256);

    /**
        @dev The time for a Loan to be funded in seconds.
     */
    function fundingPeriod() external view returns (uint256);

    /**
        @dev The time a Borrower has, after a payment is due, to make a payment before a liquidation can occur.
     */
    function defaultGracePeriod() external view returns (uint256);

    /**
        @dev The amount of principal owed (initially the drawdown amount).
     */
    function principalOwed() external view returns (uint256);

    /**
        @dev The amount of principal that has been paid by the Borrower since the Loan instantiation.
     */
    function principalPaid() external view returns (uint256);

    /**
        @dev The amount of interest that has been paid by the Borrower since the Loan instantiation.
     */
    function interestPaid() external view returns (uint256);

    /**
        @dev The amount of fees that have been paid by the Borrower since the Loan instantiation.
     */
    function feePaid() external view returns (uint256);

    /**
        @dev The amount of excess that has been returned to the Lenders after the Loan drawdown.
     */
    function excessReturned() external view returns (uint256);

    /**
        @dev The amount of Collateral Asset that has been liquidated after default.
     */
    function amountLiquidated() external view returns (uint256);

    /**
        @dev The amount of Liquidity Asset that has been recovered after default.
     */
    function amountRecovered() external view returns (uint256);

    /**
        @dev The difference between `amountRecovered` and `principalOwed` after liquidation.
     */
    function defaultSuffered() external view returns (uint256);

    /**
        @dev The amount of Liquidity Asset that is to be returned to the Borrower, if `amountRecovered > principalOwed`.
     */
    function liquidationExcess() external view returns (uint256);

    /**
        @dev   Draws down funding from FundingLocker, posts collateral, and transitions the Loan state from `Ready` to `Active`. 
        @dev   Only the Borrower can call this function. 
        @dev   It emits four `BalanceUpdated` events. 
        @dev   It emits a `LoanStateChanged` event. 
        @dev   It emits a `Drawdown` event. 
        @param amt the amount of Liquidity Asset the Borrower draws down. Remainder is returned to the Loan where it can be claimed back by LoanFDT holders.
     */
    function drawdown(uint256 amt) external;

    /**
        @dev Makes a payment for this Loan. 
        @dev Amounts are calculated for the Borrower. 
     */
    function makePayment() external;

    /**
        @dev Makes the full payment for this Loan (a.k.a. "calling" the Loan). 
        @dev This requires the Borrower to pay a premium fee. 
     */
    function makeFullPayment() external;
    
    /**
        @dev   Funds this Loan and mints LoanFDTs for `mintTo` (DebtLocker in the case of Pool funding). 
        @dev   Only LiquidityLocker using valid/approved Pool can call this function. 
        @dev   It emits a `LoanFunded` event. 
        @dev   It emits a `BalanceUpdated` event. 
        @param mintTo The address that LoanFDTs are minted to.
        @param amt    The amount to fund the Loan.
     */
    function fundLoan(address mintTo, uint256 amt) external;

    /**
        @dev Handles returning capital to the Loan, where it can be claimed back by LoanFDT holders, 
             if the Borrower has not drawn down on the Loan past the drawdown grace period. 
        @dev It emits a `LoanStateChanged` event. 
     */
    function unwind() external;

    /**
        @dev Triggers a default if the Loan meets certain default conditions, liquidating all collateral and updating accounting. 
        @dev Only the an account with sufficient LoanFDTs of this Loan can call this function. 
        @dev It emits a `BalanceUpdated` event. 
        @dev It emits a `Liquidation` event. 
        @dev It emits a `LoanStateChanged` event. 
     */
    function triggerDefault() external;

    /**
        @dev Triggers paused state. 
        @dev Halts functionality for certain functions. Only the Borrower or a Loan Admin can call this function. 
     */
    function pause() external;

    /**
        @dev Triggers unpaused state. 
        @dev Restores functionality for certain functions. 
        @dev Only the Borrower or a Loan Admin can call this function. 
     */
    function unpause() external;

    /**
        @dev   Sets a Loan Admin. 
        @dev   Only the Borrower can call this function. 
        @dev   It emits a `LoanAdminSet` event. 
        @param loanAdmin The address being allowed or disallowed as a Loan Admin.
        @param allowed   The atatus of a Loan Admin.
     */
    function setLoanAdmin(address loanAdmin, bool allowed) external;

    /**
        @dev   Transfers any locked funds to the Governor. 
        @dev   Only the Governor can call this function. 
        @param token The address of the token to be reclaimed.
     */
    function reclaimERC20(address token) external;

    /**
        @dev Withdraws all available funds earned through LoanFDT for a token holder. 
        @dev It emits a `BalanceUpdated` event. 
     */
    function withdrawFunds() external override;

    /**
        @dev    Returns the expected amount of Liquidity Asset to be recovered from a liquidation based on current oracle prices.
        @return The minimum amount of Liquidity Asset that can be expected by swapping Collateral Asset.
     */
    function getExpectedAmountRecovered() external view returns (uint256);

    /**
        @dev    Returns information of the next payment amount.
        @return The entitled interest of the next payment (Principal + Interest only when the next payment is last payment of the Loan).
        @return The entitled principal amount needed to be paid in the next payment.
        @return The entitled interest amount needed to be paid in the next payment.
        @return The payment due date.
        @return Whether the payment is late.
     */
    function getNextPayment() external view returns (uint256, uint256, uint256, uint256, bool);

    /**
        @dev    Returns the information of a full payment amount.
        @return total     Principal and interest owed, combined.
        @return principal Principal owed.
        @return interest  Interest owed.
     */
    function getFullPayment() external view returns (uint256 total, uint256 principal, uint256 interest);

    /**
        @dev    Calculates the collateral required to draw down amount.
        @param  amt The amount of the Liquidity Asset to draw down from the FundingLocker.
        @return The amount of the Collateral Asset required to post in the CollateralLocker for a given drawdown amount.
     */
    function collateralRequiredForDrawdown(uint256 amt) external view returns (uint256);

}
