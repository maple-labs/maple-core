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
        @param  _loan Loan to calculate a payment for
        @return [0] = Entitiled interest to the next payment, Principal + Interest only when the next payment is last payment of the loan
                [1] = Entitiled principal amount needs to pay in the next payment
                [2] = Entitiled interest amount needs to pay in the next payment
    */
    function getNextPayment(address _loan) view public returns(uint256, uint256, uint256) {

        ILoan loan = ILoan(_loan);

        uint256 principalOwed = loan.principalOwed();

        // Equation = principal * APR * (paymentInterval / year)
        // Principal * APR gives annual interest
        // Multiplying that by (paymentInterval / year) gives portion of annual interest due for each interval
        uint256 interest = 
            principalOwed
                .mul(loan.apr())
                .mul(loan.paymentIntervalSeconds())
                .div(10_000)
                .div(365 days);

        if (loan.paymentsRemaining() == 1) {
            return (interest.add(principalOwed), principalOwed, interest); 
        } else {
            return (interest, 0, interest); 
        }
    }
} 
