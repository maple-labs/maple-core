// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

interface ILateFeeCalc {
    function getLateFee(uint256) external view returns (uint256);
} 
