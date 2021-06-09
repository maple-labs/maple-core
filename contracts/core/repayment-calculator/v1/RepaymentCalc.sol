// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";

import "core/loan/v1/interfaces/ILoan.sol";

import "./interfaces/IRepaymentCalc.sol";

/// @title RepaymentCalc calculates payment amounts on Loans.
contract RepaymentCalc is IRepaymentCalc {

	using SafeMath for uint256;

    uint8   public override constant calcType = 10;
    bytes32 public override constant name     = "INTEREST_ONLY";

    function getNextPayment(address loan) external override view returns (uint256 total, uint256 principalOwed, uint256 interest) {

        ILoan _loan = ILoan(loan);

        principalOwed = _loan.principalOwed();

        // Equation = principal * APR * (paymentInterval / year)
        // Principal * APR gives annual interest
        // Multiplying that by (paymentInterval / year) gives portion of annual interest due for each interval.
        interest =
            principalOwed
                .mul(_loan.apr())
                .mul(_loan.paymentIntervalSeconds())
                .div(10_000)
                .div(365 days);

        (total, principalOwed) = _loan.paymentsRemaining() == 1
            ? (interest.add(principalOwed), principalOwed)
            : (interest, 0);
    }

}
