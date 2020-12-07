// SPDX-License-Identifier: MIT
pragma solidity 0.7.0;

interface IStakeLockerFactory {
    function newLocker(
        address _stakeAsset,
        address _liquidityAsset,
        address _globals
    ) external returns (address);
}