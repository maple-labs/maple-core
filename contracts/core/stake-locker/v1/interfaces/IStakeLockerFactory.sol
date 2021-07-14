// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { ISubFactory } from "../../../subfactory/v1/interfaces/ISubFactory.sol";

/// @title StakeLockerFactory instantiates StakeLockers.
interface IStakeLockerFactory is ISubFactory {

    /**
        @dev   Emits an event indicating a StakeLocker was created.
        @param owner          The owner of the StakeLocker.
        @param stakeLocker    The address of the StakeLocker.
        @param stakeAsset     The Stake Asset this StakeLocker will escrow.
        @param liquidityAsset The address of the Liquidity Asset (as defined in the Pool).
        @param name           The name of the StakeLockerFDTs.
        @param symbol         The symbol of the StakeLockerFDTs.
     */
    event StakeLockerCreated(
        address indexed owner,
        address stakeLocker,
        address stakeAsset,
        address liquidityAsset,
        string name,
        string symbol
    );

    /**
        @param  stakeLocker The address of a StakeLocker.
        @return The address of the owner of StakeLocker at `stakeLocker`.
     */
    function owner(address stakeLocker) external returns (address);

    /**
        @param  stakeLocker Some address.
        @return Whether `stakeLocker` is a StakeLocker.
     */
    function isLocker(address stakeLocker) external returns (bool);

    /**
        @dev The type of the factory (i.e FactoryType::STAKE_LOCKER_FACTORY).
     */
    function factoryType() external override pure returns (uint8);

    /**
        @dev    Instantiate a StakeLocker.
        @dev    It emits a `StakeLockerCreated` event.
        @param  stakeAsset     The address of the Stake Asset (generally Balancer Pool BPTs).
        @param  liquidityAsset The address of the Liquidity Asset (as defined in the Pool).
        @return stakeLocker    The address of the instantiated StakeLocker.
     */
    function newLocker(address stakeAsset, address liquidityAsset) external returns (address stakeLocker);

}
