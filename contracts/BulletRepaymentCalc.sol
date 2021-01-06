// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "./interfaces/ILoan.sol";

contract BulletRepaymentCalc {

	using SafeMath for uint256;

    bytes32 public calcType = "INTEREST";
    bytes32 public name = "BULLET";

    /// @dev Returns the total value of next payment, and interest/principal amount.
    /// @return (uint256,uint256,uint256) [0] = Principal + Interest, [1] = Principal, [2] = Interest
    function getNextPayment(address _loan) view public returns(uint256, uint256, uint256) {

        ILoan loan = ILoan(_loan);

        uint256 principalOwed       = loan.principalOwed();
        uint256 apr                 = loan.apr();
        uint256 paymentIntervalDays = loan.paymentIntervalSeconds().div(86400);
        uint256 paymentsRemaining   = loan.paymentsRemaining();

        // principalOwed.mul(apr).div(10000) represents interest amount for an annual time-frame.
        // .mul(paymentIntervalDays).div(365) is the annual interest amount adjusted for actual time-frame.
        uint256 interest = principalOwed.mul(apr).div(10000).mul(paymentIntervalDays).div(365);

        if (paymentsRemaining == 1) {
            return (interest.add(principalOwed), principalOwed, interest); 
        } else {
            return (interest, 0, interest); 
        }
    }
} 
