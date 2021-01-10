// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "./interfaces/ILoan.sol";

/// @title LateFeeCalc applies a flat fee on the amount owed for next payment.
contract LateFeeCalc {

    using SafeMath for uint256;

    bytes32 public calcType = 'LATEFEE';
    bytes32 public name     = 'NULL';
    
    uint256 public feeBips;  // The fee in bips, charged on the payment amount.

    constructor(uint256 _feeBips) public {
        feeBips = _feeBips;
    }

    /**
        @dev    Calculates the late fee payment for a _loan.
        @param  _loan is the Loan to calculate late fee for.
        @return [0] = Principal + Interest (Total)
                [1] = Principal
                [2] = Interest
    */
    function getLateFee(address _loan) view public returns(uint256, uint256, uint256) {
        ILoan loan           = ILoan(_loan);
        (uint paymentDue,,,) = loan.getNextPayment();
        return (paymentDue.mul(feeBips).div(10000), 0, paymentDue.mul(feeBips).div(10000));
    }
} 
