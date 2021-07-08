// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "../../../../lib/openzeppelin-contracts/contracts/math/SafeMath.sol";

import "../../../../core/loan/v1/interfaces/ILoan.sol";

import "./interfaces/IRepaymentCalc.sol";

/// @title RepaymentCalc calculates payment amounts on Loans.
contract RepaymentCalc is IRepaymentCalc {

	using SafeMath for uint256;

    uint8   public override constant calcType = 10;               // INTEREST type.
    bytes32 public override constant name     = "INTEREST_ONLY";

    function getNextPayment(address _loan) external override view returns (uint256 total, uint256 principalOwed, uint256 interest) {

        ILoan loan = ILoan(_loan);

        principalOwed = loan.principalOwed();

        // Equation = principal * APR * (paymentInterval / year)
        // Principal * APR gives annual interest
        // Multiplying that by (paymentInterval / year) gives portion of annual interest due for each interval.
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
