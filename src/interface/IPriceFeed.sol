// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

interface IPriceFeed {
    function price() external view returns (uint256);
}
