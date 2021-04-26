// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "./LiquidityLocker.sol";

/// @title LiquidityLockerFactory instantiates LiquidityLockers.
contract LiquidityLockerFactory {

    mapping(address => address) public owner;     // Mapping of locker contract address to its owner i.e owner[locker] = Owner of the liquidity locker
    mapping(address => bool)    public isLocker;  // True if liquidity locker was created by this factory, otherwise false

    uint8 public constant factoryType = 3;        // i.e LockerFactoryTypes::LIQUIDITY_LOCKER_FACTORY

    event LiquidityLockerCreated(address indexed owner, address liquidityLocker, address liquidityAsset);

    /**
        @dev Instantiate a LiquidityLocker contract.
        @dev It emits a `LiquidityLockerCreated` event.
        @param  liquidityAsset The asset this liquidity locker will escrow
        @return Address of the instantiated liquidity locker
    */
    function newLocker(address liquidityAsset) external returns (address) {
        address liquidityLocker   = address(new LiquidityLocker(liquidityAsset, msg.sender));
        owner[liquidityLocker]    = msg.sender;
        isLocker[liquidityLocker] = true;

        emit LiquidityLockerCreated(msg.sender, liquidityLocker, liquidityAsset);
        return liquidityLocker;
    }
}
