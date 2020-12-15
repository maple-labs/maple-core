// SPDX-License-Identifier: MIT
pragma solidity 0.7.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "../interface/ILoanVault.sol";

contract BulletRepaymentCalculator {

	using SafeMath for uint256;

  /// @dev Returns the total value of next payment, and interest/principal amount.
  /// @return (uint,uint,uint) [0] = Principal + Interest, [1] = Principal, [2] = Interest
  function getNextPayment(address _loanVault) view public returns(uint, uint, uint) {

    ILoanVault loan = ILoanVault(_loanVault);
    uint principalOwed = loan.principalOwed();
    uint aprBips = loan.aprBips();
    uint paymentIntervalDays = loan.paymentIntervalSeconds().div(86400);
    uint paymentsRemaining = loan.numberOfPayments();

    // principalOwed.mul(aprBips).div(10000) represents interest amount for an annual time-frame.
    // .mul(paymentIntervalDays).div(365) is the annual interest amount adjusted for actual time-frame.
    uint interest = principalOwed.mul(aprBips).div(10000).mul(paymentIntervalDays).div(365);

    if (paymentsRemaining == 1) {
      return (interest.add(principalOwed), principalOwed, interest); 
    }
    else {
      return (interest, 0, interest); 
    }

  }

} 