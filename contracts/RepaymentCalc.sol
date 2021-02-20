// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "./interfaces/ILoan.sol";

import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";

contract RepaymentCalc {

	using SafeMath for uint256;

    uint8   public constant calcType = 10;  // INTEREST type
    bytes32 public constant name     = "INTEREST_ONLY";

    /**
        @dev    Calculates the next payment for a _loan.
        @param  _loan is the Loan to calculate a payment for.
        @return [0] = Principal + Interest
                [1] = Principal
                [2] = Interest
    */
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
