// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

interface IBFactory {
    function isBPool(address b) external view returns (bool);
}
