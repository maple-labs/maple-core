// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { SafeMath } from "../../../../lib/openzeppelin-contracts/contracts/math/SafeMath.sol";

import { ILateFeeCalc } from "./interfaces/ILateFeeCalc.sol";

/// @title LateFeeCalc calculates late fees on Loans.
contract LateFeeCalc is ILateFeeCalc {

    using SafeMath for uint256;

    uint8   public override constant calcType = 11;      // LATEFEE type.
    bytes32 public override constant name     = "FLAT";

    uint256 public override immutable lateFee;

    constructor(uint256 _lateFee) public {
        lateFee = _lateFee;
    }

    function getLateFee(uint256 interest) external override view returns (uint256) {
        return interest.mul(lateFee).div(10_000);
    }

}
