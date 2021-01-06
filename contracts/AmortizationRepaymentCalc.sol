// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "./interfaces/ILoan.sol";

contract AmortizationRepaymentCalc {

	using SafeMath for uint256;

    bytes32 public calcType = "INTEREST";
    bytes32 public name = "AMORTIZATION";

    uint256 constant FIFTY   = 50 ether;
    uint256 constant HUNDRED = 100 ether;

    /// @dev Returns the total value of next payment, and interest/principal amount.
    /// @return (uint256,uint256,uint256) [0] = Principal + Interest, [1] = Principal, [2] = Interest
    function getNextPayment(address _loan) view public returns(uint256, uint256, uint256) {

        ILoan loan = ILoan(_loan);

        uint256 principalOwed       = loan.principalOwed();
        uint256 paymentsRemaining   = loan.paymentsRemaining();
        uint256 apr                 = loan.apr();
        uint256 paymentIntervalDays = loan.paymentIntervalSeconds().div(86400);
        uint256 drawdownAmount      = loan.drawdownAmount();
        
        // Represents amortization by flattening the total interest owed for equal interest payments.
        uint256 interestAnnual  = drawdownAmount.mul(apr).div(10000).mul(paymentIntervalDays).div(365);
        uint256 interestPartial = FIFTY.div(paymentsRemaining).add(FIFTY);
        uint256 interest        = interestAnnual.mul(interestPartial).div(HUNDRED);
        uint256 principal       = principalOwed.div(paymentsRemaining);

    	return (interest.add(principal), principal, interest);
  	}
}
