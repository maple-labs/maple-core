// SPDX-License-Identifier: AGPL-3.0-or-later
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
        @dev    Calculates the late fee payment for a loan.
        @param  interest Amount of interest to be used to calculate late fee for
        @return Late fee that charged to borrower
    */
    function getLateFee(uint256 interest) view public returns(uint256) {
        return interest.mul(lateFee).div(10_000);
    }
} 
