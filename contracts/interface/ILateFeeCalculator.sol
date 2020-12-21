// SPDX-License-Identifier: MIT
pragma solidity 0.7.0;

interface ILateFeeCalculator {
    function getLateFee(address) external view returns (uint256, uint256, uint256);
} 