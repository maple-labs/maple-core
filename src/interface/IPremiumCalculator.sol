// SPDX-License-Identifier: MIT
pragma solidity 0.7.0;

interface IPremiumCalculator {
    function getPremiumPayment(address) external view returns (uint256, uint256, uint256);
} 