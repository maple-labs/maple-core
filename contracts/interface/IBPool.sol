// SPDX-License-Identifier: MIT
pragma solidity 0.7.0;

interface IBPool {
    function isFinalized() external view returns (bool);

    function isBound(address) external view returns (bool);

    function getNumTokens() external view returns (uint256);

    function getBalance(address) external view returns (uint256);

    function getNormalizedWeight(address) external view returns (uint256);
}
