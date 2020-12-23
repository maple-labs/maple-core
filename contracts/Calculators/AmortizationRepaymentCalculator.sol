// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "../interface/ILoanVault.sol";

contract AmortizationRepaymentCalculator {

	using SafeMath for uint256;

  /// @dev Returns the total value of next payment, and interest/principal amount.
  /// @return (uint256,uint256,uint256) [0] = Principal + Interest, [1] = Principal, [2] = Interest
  function getNextPayment(address _loanVault) view public returns(uint256, uint256, uint256) {

    ILoanVault loan = ILoanVault(_loanVault);
    uint256 principalOwed = loan.principalOwed();
    uint256 paymentsRemaining = loan.numberOfPayments();
    uint256 aprBips = loan.aprBips();
    uint256 paymentIntervalDays = loan.paymentIntervalSeconds().div(86400);
    uint256 drawdownAmount = loan.drawdownAmount();
    uint256 fifty = 50;
    uint256 hundred = 100;

    // Represents amortization by flattening the total interest owed for equal interest payments.
    uint256 interestAnnual = drawdownAmount.mul(aprBips).div(10000).mul(paymentIntervalDays).div(365);
    uint256 interestPartial = fifty.mul(1 ether).div(paymentsRemaining).add(fifty.mul(1 ether));
    uint256 interest = interestAnnual.mul(interestPartial).div(hundred.mul(1 ether));
    uint256 principal = principalOwed.div(paymentsRemaining);

    return (interest.add(principal), principal, interest);

  }

} 
