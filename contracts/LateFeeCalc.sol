// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "./interfaces/ILoan.sol";
import "./interfaces/IRepaymentCalc.sol";

import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";

/// @title LateFeeCalc applies a flat fee on the amount owed for next payment.
contract LateFeeCalc {

    using SafeMath for uint256;

    uint8   public constant calcType = 11;  // "LATEFEE type"
    bytes32 public constant name     = 'FLAT';
    
    uint256 public feeBips;  // The fee in bips, charged on the payment amount.

    constructor(uint256 _feeBips) public {
        feeBips = _feeBips;
    }

    /**
        @dev    Calculates the late fee payment for a _loan.
        @param  loan is the Loan to calculate late fee for.
        @return [0] = Principal + Interest (Total)
                [1] = Principal
                [2] = Interest
    */
    function getLateFee(address loan) view public returns(uint256, uint256, uint256) {
        IRepaymentCalc repaymentCalc = IRepaymentCalc(ILoan(loan).repaymentCalc());
        (,, uint256 paymentDue)      = repaymentCalc.getNextPayment(loan);
        uint256 lateFee              = paymentDue.mul(feeBips).div(10000);
        return (lateFee, 0, lateFee);
    }
} 
