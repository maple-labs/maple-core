// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

interface ICollateralLockerFactory {
    function newLocker(address) external returns (address);
}
