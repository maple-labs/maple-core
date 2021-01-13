// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

interface IBFactory {
    function factoryType() external returns (bytes32);
}