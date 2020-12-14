// SPDX-License-Identifier: MIT
pragma solidity 0.7.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "../interface/ILoanVault.sol";

contract AmortizationRepaymentCalculator {

	using SafeMath for uint256;

  /// @dev Returns the total value of next payment, and interest/principal amount.
  /// @return (uint,uint,uint) [0] = Principal + Interest, [1] = Principal, [2] = Interest
  function getNextPayment(address _loanVault) view public returns(uint, uint, uint) {

    ILoanVault loan = ILoanVault(_loanVault);
    uint principalOwed = loan.principalOwed();
    uint paymentsRemaining = loan.numberOfPayments();
    uint aprBips = loan.aprBips();
    uint paymentIntervalDays = loan.paymentIntervalSeconds().div(86400);
    uint drawdownAmount = loan.drawdownAmount();

    // Represents amortization by flattening the total interest owed for equal interest payments.
    uint interestAnnual = drawdownAmount.mul(aprBips).div(10000).mul(paymentIntervalDays).div(365);
    uint interestPartial = ((50 * 10**18) / paymentsRemaining).add(50 * 10**18);
    uint principal = principalOwed.mul(paymentsRemaining);
    uint interest = interestAnnual.mul(interestPartial).div(100 * 10**18);

    return (interest.add(principal), principal, interest);

  }

} 