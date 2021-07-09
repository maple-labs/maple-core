// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { Pausable } from "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";

import { IMapleGlobals } from "core/globals/v1/interfaces/IMapleGlobals.sol";

import { IPoolFactory } from "./interfaces/IPoolFactory.sol";

import { Pool } from "./Pool.sol";

/// @title PoolFactory instantiates Pools.
contract PoolFactory is IPoolFactory, Pausable {

    uint8 public override constant LL_FACTORY = 3;
    uint8 public override constant SL_FACTORY = 4;

    uint256 public override poolsCreated;
    IMapleGlobals public override globals;

    mapping(uint256 => address) public override pools;
    mapping(address => bool)    public override isPool;             // True only if a Pool was instantiated by this factory.
    mapping(address => bool)    public override poolFactoryAdmins;

    constructor(address _globals) public {
        globals = IMapleGlobals(_globals);
    }

    function setGlobals(address newGlobals) external override {
        _isValidGovernor();
        globals = IMapleGlobals(newGlobals);
    }

    function createPool(
        address liquidityAsset,
        address stakeAsset,
        address slFactory,
        address llFactory,
        uint256 stakingFee,
        uint256 delegateFee,
        uint256 liquidityCap
    ) external override whenNotPaused returns (address poolAddress) {
        _whenProtocolNotPaused();
        {
            IMapleGlobals _globals = globals;
            require(_globals.isValidSubFactory(address(this), llFactory, LL_FACTORY), "PF:INVALID_LLF");
            require(_globals.isValidSubFactory(address(this), slFactory, SL_FACTORY), "PF:INVALID_SLF");
            require(_globals.isValidPoolDelegate(msg.sender),                         "PF:NOT_DELEGATE");
        }

        string memory name   = "Maple Pool Token";
        string memory symbol = "MPL-LP";

        Pool pool =
            new Pool(
                msg.sender,
                liquidityAsset,
                stakeAsset,
                slFactory,
                llFactory,
                stakingFee,
                delegateFee,
                liquidityCap,
                name,
                symbol
            );

        poolAddress         = address(pool);
        pools[poolsCreated] = poolAddress;
        isPool[poolAddress] = true;
        ++poolsCreated;

        emit PoolCreated(
            poolAddress,
            msg.sender,
            liquidityAsset,
            stakeAsset,
            pool.liquidityLocker(),
            pool.stakeLocker(),
            stakingFee,
            delegateFee,
            liquidityCap,
            name,
            symbol
        );
    }

    function setPoolFactoryAdmin(address poolFactoryAdmin, bool allowed) external override {
        _isValidGovernor();
        poolFactoryAdmins[poolFactoryAdmin] = allowed;
        emit PoolFactoryAdminSet(poolFactoryAdmin, allowed);
    }

    function pause() external override {
        _isValidGovernorOrPoolFactoryAdmin();
        super._pause();
    }

    function unpause() external override {
        _isValidGovernorOrPoolFactoryAdmin();
        super._unpause();
    }

    /**
        @dev Checks that `msg.sender` is the Governor.
     */
    function _isValidGovernor() internal view {
        require(msg.sender == globals.governor(), "PF:NOT_GOV");
    }

    /**
        @dev Checks that `msg.sender` is the Governor or a PoolFactory Admin.
     */
    function _isValidGovernorOrPoolFactoryAdmin() internal view {
        require(msg.sender == globals.governor() || poolFactoryAdmins[msg.sender], "PF:NOT_GOV_OR_ADMIN");
    }

    /**
        @dev Checks that the protocol is not in a paused state.
     */
    function _whenProtocolNotPaused() internal view {
        require(!globals.protocolPaused(), "PF:PROTO_PAUSED");
    }

}
