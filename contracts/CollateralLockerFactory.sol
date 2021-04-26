// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "./CollateralLocker.sol";

import "./interfaces/ILoanFactory.sol";

/// @title CollateralLockerFactory instantiates CollateralLockers.
contract CollateralLockerFactory {

    mapping(address => address) public owner;     // Mapping of locker contract address to its owner i.e owner[locker] = Owner of the collateral locker
    mapping(address => bool)    public isLocker;  // True if collateral locker was created by this factory, otherwise false

    uint8 public constant factoryType = 0;  // i.e FactoryType::COLLATERAL_LOCKER_FACTORY

    event CollateralLockerCreated(address indexed owner, address collateralLocker, address collateralAsset);

    /**
        @dev Instantiate a CollateralLocker contract.
        @dev It emits a `CollateralLockerCreated` event.
        @param collateralAsset The asset this collateral locker will escrow.
        @return collateralLocker Address of the instantiated collateral locker.
    */
    function newLocker(address collateralAsset) external returns (address collateralLocker) {
        collateralLocker           = address(new CollateralLocker(collateralAsset, msg.sender));
        owner[collateralLocker]    = msg.sender;
        isLocker[collateralLocker] = true;

        emit CollateralLockerCreated(msg.sender, collateralLocker, collateralAsset);
    }
}
