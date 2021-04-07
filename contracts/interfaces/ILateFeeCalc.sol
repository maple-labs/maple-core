// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

interface ILateFeeCalc {
    function getLateFee(uint256) external view returns (uint256);
} 
