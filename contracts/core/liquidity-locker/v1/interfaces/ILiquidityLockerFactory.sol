// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

interface ILiquidityLockerFactory {

    function owner(address) external view returns (address);

    function isLocker(address) external view returns (bool);

    function factoryType() external view returns (uint8);

    function newLocker(address) external returns (address);

}
