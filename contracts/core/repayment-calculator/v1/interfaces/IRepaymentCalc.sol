// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { ICalc } from "core/calculator/v1/interfaces/ICalc.sol";

/// @title RepaymentCalc calculates payment amounts on Loans.
interface IRepaymentCalc is ICalc {

    /**
        @dev    Calculates the next payment for a Loan.
        @param  _loan         The address of a Loan to calculate a payment for.
        @return total         The entitled interest of the next payment (Principal + Interest only when the next payment is last payment of the Loan).
        @return principalOwed The entitled principal amount needed to be paid in the next payment.
        @return interest      The entitled interest amount needed to be paid in the next payment.
     */
    function getNextPayment(address _loan) external view returns (uint256 total, uint256 principalOwed, uint256 interest);

}
