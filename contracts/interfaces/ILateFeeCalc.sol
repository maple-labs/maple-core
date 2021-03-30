// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

interface ILateFeeCalc {
    function getLateFee(address) external view returns (uint256);
} 
