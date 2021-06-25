// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

/// @title LateFeeCalc calculates late fees on Loans.
interface ILateFeeCalc {

    /**
        @dev The Calculator type.
     */
    function calcType() external view returns (uint8);

    /**
        @dev The Calculator name.
     */
    function name() external view returns (bytes32);

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
