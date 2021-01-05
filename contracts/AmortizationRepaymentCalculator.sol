// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "./math/math.sol";
import "./interfaces/ILoanVault.sol";

contract AmortizationRepaymentCalculator is DSMath {

    bytes32 public calcType = "INTEREST";
    bytes32 public name = "AMORTIZATION";

    /// @dev Returns the total value of next payment, and interest/principal amount.
    /// @return (uint256,uint256,uint256) [0] = Principal + Interest, [1] = Principal, [2] = Interest
    function getNextPayment(address _loanVault) view public returns(uint256, uint256, uint256) {

        ILoanVault loan = ILoanVault(_loanVault);

        uint256 principalOwed       = loan.principalOwed();
        uint256 paymentsRemaining   = loan.numberOfPayments();
        uint256 aprBips             = loan.aprBips();
        uint256 paymentIntervalDays = loan.paymentIntervalSeconds() / 1 days;
        uint256 drawdownAmount      = loan.drawdownAmount();

        // Represents amortization by flattening the total interest owed for equal interest payments.
        uint256 interestAnnual  = mul(mul(drawdownAmount, aprBips) / 1000, paymentIntervalDays) / 365; 
        uint256 interestPartial = 50 ether / paymentsRemaining + 50 ether;
        uint256 interest        = mul(interestAnnual, interestPartial) / 100 ether;
        uint256 principal       = principalOwed / paymentsRemaining;

    return (add(interest, principal), principal, interest);
  }
}
