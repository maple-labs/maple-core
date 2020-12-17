// SPDX-License-Identifier: MIT
pragma solidity 0.7.0;

interface ILiquidityLockerFactory {
    function newLocker(address _liquidityAsset) external returns (address);

    function isLiquidityLocker(address _locker) external returns (bool);

}
