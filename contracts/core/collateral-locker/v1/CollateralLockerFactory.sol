// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { ICollateralLockerFactory } from "./interfaces/ICollateralLockerFactory.sol";

import { CollateralLocker } from "./CollateralLocker.sol";

/// @title CollateralLockerFactory instantiates CollateralLockers.
contract CollateralLockerFactory is ICollateralLockerFactory {

    mapping(address => address) public override owner;     // Owners of respective CollateralLockers.
    mapping(address => bool)    public override isLocker;  // True only if a CollateralLocker was created by this factory.

    uint8 public override constant factoryType = 0;

    function newLocker(address collateralAsset) external override returns (address collateralLocker) {
        collateralLocker           = address(new CollateralLocker(collateralAsset, msg.sender));
        owner[collateralLocker]    = msg.sender;
        isLocker[collateralLocker] = true;

        emit CollateralLockerCreated(msg.sender, collateralLocker, collateralAsset);
    }

}
