// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

import "./interfaces/ILoan.sol";
import "./interfaces/IRepaymentCalc.sol";

import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";

/// @title LateFeeCalc calculates late fees on Loans.
contract LateFeeCalc {

    using SafeMath for uint256;

    uint8   public constant calcType = 11;  // "LATEFEE type"
    bytes32 public constant name     = 'FLAT';
    
    uint256 public immutable lateFee;  // The fee in basis points, charged on the payment amount.

    constructor(uint256 _lateFee) public {
        lateFee = _lateFee;
    }

    /**
        @dev    Calculates the late fee payment for a _loan.
        @param  loan Address of the Loan to calculate late fee for
        @return Late fee to be added to interest
    */
    function getLateFee(address loan) view public returns(uint256) {
        IRepaymentCalc repaymentCalc = IRepaymentCalc(ILoan(loan).repaymentCalc());
        (,, uint256 interest)        = repaymentCalc.getNextPayment(loan);
        return interest.mul(lateFee).div(10000);
    }
} 
