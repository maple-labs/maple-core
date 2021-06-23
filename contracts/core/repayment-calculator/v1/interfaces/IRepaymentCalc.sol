// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

/// @title RepaymentCalc calculates payment amounts on Loans.
interface IRepaymentCalc {

    /**
        @dev The Calculator type: INTEREST type.
     */
    function calcType() external view returns (uint8);

    /**
        @dev The name of the Calculator.
     */
    function name() external view returns (bytes32);

    /**
        @dev    Calculates the next payment for a Loan.
        @param  _loan         The address of a Loan to calculate a payment for.
        @return total         The entitled interest of the next payment (Principal + Interest only when the next payment is last payment of the Loan).
        @return principalOwed The entitled principal amount needed to be paid in the next payment.
        @return interest      The entitled interest amount needed to be paid in the next payment.
     */
    function getNextPayment(address _loan) external view returns (uint256 total, uint256 principalOwed, uint256 interest);

}
