// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

interface ICollateralLockerFactory {
    function newLocker(address) external returns (address);
    function owner(address) external returns (address);
    function isLocker(address) external returns (bool);
}
