// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "./StakeLocker.sol";

/// @title StakeLockerFactory instantiates StakeLockers.
contract StakeLockerFactory {

    mapping(address => address) public owner;     // owner[locker] = Owner of the stake locker.
    mapping(address => bool)    public isLocker;  // True if stake locker was created by this factory, otherwise false.

    uint8 public constant factoryType = 4;  // i.e FactoryType::STAKE_LOCKER_FACTORY.

    event StakeLockerCreated(
        address indexed owner,
        address stakeLocker,
        address stakeAsset,
        address liquidityAsset,
        string name,
        string symbol
    );

    /**
        @dev    Instantiate a StakeLocker contract.
        @dev    It emits a `StakeLockerCreated` event.
        @param  stakeAsset     Address of the stakeAsset (generally Balancer Pool BPTs).
        @param  liquidityAsset Address of the liquidityAsset (as defined in the pool).
        @return stakeLocker    Address of the instantiated StakeLocker.
    */
    function newLocker(
        address stakeAsset,
        address liquidityAsset
    ) external returns (address stakeLocker) {
        stakeLocker           = address(new StakeLocker(stakeAsset, liquidityAsset, msg.sender));
        owner[stakeLocker]    = msg.sender;
        isLocker[stakeLocker] = true;

        emit StakeLockerCreated(
            msg.sender,
            stakeLocker,
            stakeAsset,
            liquidityAsset,
            StakeLocker(stakeLocker).name(),
            StakeLocker(stakeLocker).symbol()
        );
    }
}
