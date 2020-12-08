// SPDX-License-Identifier: MIT
pragma solidity 0.7.0;

interface IPriceFeed {
    function price() external view returns (uint256);
}