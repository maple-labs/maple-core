// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { ILiquidityLockerFactory } from "./interfaces/ILiquidityLockerFactory.sol";

import { LiquidityLocker } from "./LiquidityLocker.sol";

/// @title LiquidityLockerFactory instantiates LiquidityLockers.
contract LiquidityLockerFactory is ILiquidityLockerFactory {

    mapping(address => address) public override owner;     /// Owners of respective LiquidityLockers.
    mapping(address => bool)    public override isLocker;  // True only if a LiquidityLocker was created by this factory.

    uint8 public override constant factoryType = 3;

    function newLocker(address liquidityAsset) external override returns (address liquidityLocker) {
        liquidityLocker           = address(new LiquidityLocker(liquidityAsset, msg.sender));
        owner[liquidityLocker]    = msg.sender;
        isLocker[liquidityLocker] = true;

        emit LiquidityLockerCreated(msg.sender, liquidityLocker, liquidityAsset);
    }

}
