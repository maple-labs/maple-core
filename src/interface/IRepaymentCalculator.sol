// SPDX-License-Identifier: MIT
pragma solidity 0.7.0;

interface IRepaymentCalculator {
    function getNextPayment(address) external view returns (uint256, uint256, uint256);
} 