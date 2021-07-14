// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { IStakeLockerFactory } from "./interfaces/IStakeLockerFactory.sol";

import { StakeLocker } from "./StakeLocker.sol";

/// @title StakeLockerFactory instantiates StakeLockers.
contract StakeLockerFactory is IStakeLockerFactory {

    mapping(address => address) public override owner;     // Owners of respective FundingLockers.
    mapping(address => bool)    public override isLocker;  // True only if a StakeLocker was created by this factory.

    uint8 public override constant factoryType = 4;

    function newLocker(
        address stakeAsset,
        address liquidityAsset
    ) external override returns (address stakeLocker) {
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
