// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "../../../../core/subfactory/v1/interfaces/ISubFactory.sol";

/// @title CollateralLockerFactory instantiates CollateralLockers.
interface ICollateralLockerFactory is ISubFactory {

    /**
        @dev   Emits an event indicating a CollateralLocker was created.
        @param owner            The owner of the CollateralLocker.
        @param collateralLocker The address of the CollateralLocker.
        @param collateralAsset  The Collateral Asset of the CollateralLocker.
     */
    event CollateralLockerCreated(address indexed owner, address collateralLocker, address collateralAsset);

    /**
        @param  collateralLocker The address of a CollateralLocker.
        @return The address of the owner of CollateralLocker at `collateralLocker`.
     */
    function owner(address collateralLocker) external view returns (address);

    /**
        @param  collateralLocker Some address.
        @return Whether `collateralLocker` is a CollateralLocker.
     */
    function isLocker(address collateralLocker) external view returns (bool);

    /**
        @dev The type of the factory (i.e FactoryType::COLLATERAL_LOCKER_FACTORY).
     */
    function factoryType() external override pure returns (uint8);

    /**
        @dev    Instantiates a CollateralLocker. 
        @dev    It emits a `CollateralLockerCreated` event. 
        @param  collateralAsset  The Collateral Asset this CollateralLocker will escrow.
        @return collateralLocker The address of the instantiated CollateralLocker.
     */
    function newLocker(address collateralAsset) external returns (address collateralLocker);

}
