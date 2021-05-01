// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "./interfaces/ILoanFactory.sol";

import "./CollateralLocker.sol";

/// @title CollateralLockerFactory instantiates CollateralLockers.
contract CollateralLockerFactory {

    mapping(address => address) public owner;     // Mapping of CollateralLocker addresses to their owner (i.e owner[locker] = Owner of the CollateralLocker).
    mapping(address => bool)    public isLocker;  // True only if a CollateralLocker was created by this factory.

    uint8 public constant factoryType = 0;  // i.e FactoryType::COLLATERAL_LOCKER_FACTORY

    event CollateralLockerCreated(address indexed owner, address collateralLocker, address collateralAsset);

    /**
        @dev    Instantiates a CollateralLocker.
        @dev    It emits a `CollateralLockerCreated` event.
        @param  collateralAsset  The Collateral Asset this CollateralLocker will escrow.
        @return collateralLocker Address of the instantiated CollateralLocker.
    */
    function newLocker(address collateralAsset) external returns (address collateralLocker) {
        collateralLocker           = address(new CollateralLocker(collateralAsset, msg.sender));
        owner[collateralLocker]    = msg.sender;
        isLocker[collateralLocker] = true;

        emit CollateralLockerCreated(msg.sender, collateralLocker, collateralAsset);
    }

}
