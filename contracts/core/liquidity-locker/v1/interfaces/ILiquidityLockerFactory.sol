// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "core/subfactory/v1/interfaces/ISubFactory.sol";

/// @title LiquidityLockerFactory instantiates LiquidityLockers.
interface ILiquidityLockerFactory is ISubFactory {

    /**
        @dev   Emits an event indicating a LiquidityLocker was created.
        @param owner           The owner of the LiquidityLocker.
        @param liquidityLocker The address of the LiquidityLocker.
        @param liquidityAsset  The Liquidity Asset of the LiquidityLocker.
     */
    event LiquidityLockerCreated(address indexed owner, address liquidityLocker, address liquidityAsset);

    /**
        @param  liquidityLocker The address of a LiquidityLocker.
        @return The address of the owner of LiquidityLocker at `liquidityLocker`.
     */
    function owner(address liquidityLocker) external view returns (address);

    /**
        @param  liquidityLocker The address of a LiquidityLocker.
        @return The address of the owner of LiquidityLocker at `liquidityLocker`.
     */
    function isLocker(address liquidityLocker) external view returns (bool);

    /**
        @dev The type of the factory (i.e FactoryType::LIQUIDITY_LOCKER_FACTORY).
     */
    function factoryType() external override pure returns (uint8);

    /**
        @dev    Instantiates a LiquidityLocker contract.
        @dev    It emits a `LiquidityLockerCreated` event.
        @param  liquidityAsset  The Liquidity Asset this LiquidityLocker will escrow.
        @return liquidityLocker The address of the instantiated LiquidityLocker.
     */
    function newLocker(address liquidityAsset) external returns (address liquidityLocker);

}
