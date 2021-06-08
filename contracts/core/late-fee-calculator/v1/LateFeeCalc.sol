// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "../../../../lib/openzeppelin-contracts/contracts/math/SafeMath.sol";

/// @title LateFeeCalc calculates late fees on Loans.
contract LateFeeCalc {

    using SafeMath for uint256;

    uint8   public constant calcType = 11;  // "LATEFEE type"
    bytes32 public constant name     = "FLAT";

    uint256 public immutable lateFee;  // The fee in basis points, charged on the payment amount.

    constructor(uint256 _lateFee) public {
        lateFee = _lateFee;
    }

    /**
        @dev    Calculates the late fee payment for a Loan.
        @param  interest Amount of interest to be used to calculate late fee for.
        @return Late fee that is charged to the Borrower.
    */
    function getLateFee(uint256 interest) external view returns (uint256) {
        return interest.mul(lateFee).div(10_000);
    }

}
