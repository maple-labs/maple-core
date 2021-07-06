// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "core/loan/v1/Loan.sol";

/// @title LoanV2 maintains all accounting and functionality related to Loans.
contract LoanV2 is Loan {

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
    ) Loan(_borrower, _liquidityAsset, _collateralAsset, _flFactory, _clFactory, specs, calcs) public {}

    function drawdown(uint256 amt) external virtual override {

        IMapleGlobals globals = _globals(superFactory);

        uint256 _feePaid = feePaid = amt.mul(globals.investorFee()).div(10_000).mul(termDays).div(365);  // Update fees paid for `claim()`.
        uint256 treasuryAmt        = amt.mul(globals.treasuryFee()).div(10_000).mul(termDays).div(365);  // Calculate amount to send to the MapleTreasury.

        // Transfer funding amount from the FundingLocker to the Borrower, then drain remaining funds to the Loan.
        _drawdown(amt, _feePaid, treasuryAmt);
    }
}