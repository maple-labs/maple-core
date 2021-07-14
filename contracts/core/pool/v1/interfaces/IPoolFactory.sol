// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { IMapleGlobals } from "../../../globals/v1/interfaces/IMapleGlobals.sol";

/// @title PoolFactory instantiates Pools.
interface IPoolFactory {

    /**
        @dev   Emits an event indicating a PoolFactoryAdmin was allowed.
        @param poolFactoryAdmin The address of a PoolFactoryAdmin.
        @param allowed          Whether `poolFactoryAdmin` is allowed as an admin of the PoolFactory.
     */
    event PoolFactoryAdminSet(address indexed poolFactoryAdmin, bool allowed);

    /**
        @dev   Emits an event indicating a Pool was created.
        @param pool             The address of the Pool.
        @param delegate         The PoolDelegate.
        @param liquidityAsset   The asset Loans will be funded in.
        @param stakeAsset       The asset stake will be locked in.
        @param liquidityLocker  The address of the LiquidityLocker.
        @param stakeLocker      The address of the StakeLocker.
        @param stakingFee       The fee paid to stakers on Loans.
        @param stakingFee       The fee paid to the Pool Delegate on Loans.
        @param liquidityCap     The maximum liquidity the Pool will hold.
        @param name             The name of the Pool FDTs.
        @param symbol           The symbol of the Pool FDTs.
     */
    event PoolCreated(
        address indexed pool,
        address indexed delegate,
        address liquidityAsset,
        address stakeAsset,
        address liquidityLocker,
        address stakeLocker,
        uint256 stakingFee,
        uint256 delegateFee,
        uint256 liquidityCap,
        string  name,
        string  symbol
    );

    /**
        @dev The factory type of `LiquidityLockerFactory`.
     */
    function LL_FACTORY() external view returns (uint8);

    /**
        @dev The factory type of `StakeLockerFactory`.
     */
    function SL_FACTORY() external view returns (uint8);

    /**
        @dev The incrementor for number of Pools created.
     */
    function poolsCreated() external view returns (uint256);

    /**
        @dev The current MapleGlobals instance.
     */
    function globals() external view returns (IMapleGlobals);

    /**
        @param  index An index of a Pool.
        @return The address of the Pool at `index`.
     */
    function pools(uint256 index) external view returns (address);

    /**
        @param  pool The address of a Pool.
        @return Whether the contract at `address` is a Pool.
     */
    function isPool(address pool) external view returns (bool);

    /**
        @param  poolFactoryAdmin The address of a PoolFactoryAdmin.
        @return Whether the `poolFactoryAdmin` has permission to do certain operations in case of disaster management
     */
    function poolFactoryAdmins(address poolFactoryAdmin) external view returns (bool);

    /**
        @dev   Sets MapleGlobals instance. 
        @dev   Only the Governor can call this function. 
        @param newGlobals The address of new MapleGlobals.
     */
    function setGlobals(address newGlobals) external;

    /**
        @dev    Instantiates a Pool. 
        @dev    It emits a `PoolCreated` event. 
        @param  liquidityAsset The asset escrowed in a LiquidityLocker.
        @param  stakeAsset     The asset escrowed in a StakeLocker.
        @param  slFactory      The factory to instantiate a StakeLocker from.
        @param  llFactory      The factory to instantiate a LiquidityLocker from.
        @param  stakingFee     The fee that Stakers earn on interest, in basis points.
        @param  delegateFee    The fee that the Pool Delegate earns on interest, in basis points.
        @param  liquidityCap   The amount of Liquidity Asset accepted by the Pool.
        @return poolAddress    The address of the instantiated Pool.
     */
    function createPool(
        address liquidityAsset,
        address stakeAsset,
        address slFactory,
        address llFactory,
        uint256 stakingFee,
        uint256 delegateFee,
        uint256 liquidityCap
    ) external returns (address poolAddress);

    /**
        @dev   Sets a PoolFactory Admin. 
        @dev   Only the Governor can call this function. 
        @dev   It emits a `PoolFactoryAdminSet` event. 
        @param poolFactoryAdmin An address being allowed or disallowed as a PoolFactory Admin.
        @param allowed          Whether `poolFactoryAdmin` is allowed as a PoolFactory Admin.
     */
    function setPoolFactoryAdmin(address poolFactoryAdmin, bool allowed) external;

    /**
        @dev Triggers paused state. 
        @dev Halts functionality for certain functions. 
        @dev Only the Governor or a PoolFactory Admin can call this function. 
     */
    function pause() external;

    /**
        @dev Triggers unpaused state. 
        @dev Restores functionality for certain functions. 
        @dev Only the Governor or a PoolFactory Admin can call this function. 
     */
    function unpause() external;

}
