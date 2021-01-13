// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

interface IBFactory {
    function type() external returns (bytes32);
}