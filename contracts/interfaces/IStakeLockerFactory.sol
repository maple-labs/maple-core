// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

interface IStakeLockerFactory {
    function newLocker(address _stakeAsset, address _liquidityAsset) external returns (address);
    function owner(address) external returns (address);
    function isLocker(address) external returns (bool);
}
