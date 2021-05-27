// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "./LiquidityLocker.sol";

/// @title LiquidityLockerFactory instantiates LiquidityLockers.
contract LiquidityLockerFactory {

    mapping(address => address) public owner;     // Mapping of LiquidityLocker addresses to their owner (i.e owner[locker] = Owner of the LiquidityLocker).
    mapping(address => bool)    public isLocker;  // True only if a LiquidityLocker was created by this factory.

    uint8 public constant factoryType = 3;        // i.e LockerFactoryTypes::LIQUIDITY_LOCKER_FACTORY

    event LiquidityLockerCreated(address indexed owner, address liquidityLocker, address liquidityAsset);

    /**
        @dev    Instantiates a LiquidityLocker contract.
        @dev    It emits a `LiquidityLockerCreated` event.
        @param  liquidityAsset  The Liquidity Asset this LiquidityLocker will escrow.
        @return liquidityLocker Address of the instantiated LiquidityLocker.
    */
    function newLocker(address liquidityAsset) external returns (address liquidityLocker) {
        liquidityLocker           = address(new LiquidityLocker(liquidityAsset, msg.sender));
        owner[liquidityLocker]    = msg.sender;
        isLocker[liquidityLocker] = true;

        emit LiquidityLockerCreated(msg.sender, liquidityLocker, liquidityAsset);
    }

}
