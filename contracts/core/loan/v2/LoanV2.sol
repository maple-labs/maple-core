// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

/// @title LoanV2 maintains all accounting and functionality related to Loans.
contract LoanV2 is LoanV1 {

    function drawdown(uint256 amt) external override {
        _preDrawdownChecksAndUpdateLoanState(amt);

        IMapleGlobals globals = _globals(superFactory);

        IFundingLocker _fundingLocker = IFundingLocker(fundingLocker);

        // Transfer funding amount from the FundingLocker to the Borrower, then drain remaining funds to the Loan.
        uint256 treasuryFee = globals.treasuryFee();
        uint256 investorFee = globals.investorFee();

        address treasury = globals.mapleTreasury();

        uint256 _feePaid = feePaid = amt.mul(investorFee).div(10_000).mul(termDays).div(365);  // Update fees paid for `claim()`.
        uint256 treasuryAmt        = amt.mul(treasuryFee).div(10_000).mul(termDays).div(365);  // Calculate amount to send to the MapleTreasury.

        _transferFunds(_fundingLocker, treasury, treasuryAmt);                         // Send the treasury fee directly to the MapleTreasury.
        _transferFunds(_fundingLocker, borrower, amt.sub(treasuryAmt).sub(_feePaid));  // Transfer drawdown amount to the Borrower.

        // Update excessReturned for `claim()`.
        excessReturned = _getFundingLockerBalance().sub(_feePaid);

        // Drain remaining funds from the FundingLocker (amount equal to `excessReturned` plus `feePaid`)
        _fundingLocker.drain();

        // Call `updateFundsReceived()` update LoanFDT accounting with funds received from fees and excess returned.
        updateFundsReceived();

        _postDrawdownEmitEvents(amt, treasury);
    }
}