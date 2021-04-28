// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "./interfaces/ILoan.sol";

import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";

/// @title RepaymentCalc calculates payment amounts on Loans.
contract RepaymentCalc {

	using SafeMath for uint256;

    uint8   public constant calcType = 10;               // INTEREST type
    bytes32 public constant name     = "INTEREST_ONLY";  // Calculator

    /**
        @dev    Calculates the next payment for a Loan.
        @param  _loan         Loan to calculate a payment for
        @return total         Entitled interest to the next payment, Principal + Interest only when the next payment is last payment of the loan.
        @return principalOwed Entitled principal amount needs to pay in the next payment.
        @return interest      Entitled interest amount needs to pay in the next payment.
    */
    function getNextPayment(address _loan) external view returns (uint256 total, uint256 principalOwed, uint256 interest) {

        ILoan loan = ILoan(_loan);

        principalOwed = loan.principalOwed();

        // Equation = principal * APR * (paymentInterval / year)
        // Principal * APR gives annual interest
        // Multiplying that by (paymentInterval / year) gives portion of annual interest due for each interval
        interest =
            principalOwed
                .mul(loan.apr())
                .mul(loan.paymentIntervalSeconds())
                .div(10_000)
                .div(365 days);

        (total, principalOwed) = loan.paymentsRemaining() == 1
            ? (interest.add(principalOwed), principalOwed)
            : (interest, 0);
    }
}
