// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { ICalc } from "core/calculator/v1/interfaces/ICalc.sol";

/// @title LateFeeCalc calculates late fees on Loans.
interface ILateFeeCalc is ICalc {

    /**
        @dev The fee in basis points, charged on the payment amount.
     */
    function lateFee() external view returns (uint256);

    /**
        @dev    Calculates the late fee payment for a Loan.
        @param  interest Amount of interest to be used to calculate late fee for.
        @return Late fee that is charged to the Borrower.
     */
    function getLateFee(uint256 interest) external view returns (uint256);

}
