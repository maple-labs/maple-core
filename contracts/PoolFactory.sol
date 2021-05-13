// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "openzeppelin-contracts/utils/Pausable.sol";

import "./Pool.sol";

/// @title PoolFactory instantiates Pools.
contract PoolFactory is Pausable {

    uint8 public constant LL_FACTORY = 3;  // Factory type of `LiquidityLockerFactory`.
    uint8 public constant SL_FACTORY = 4;  // Factory type of `StakeLockerFactory`.

    uint256  public poolsCreated;  // Incrementor for number of Pools created.
    IMapleGlobals public globals;  // A MapleGlobals instance.

    mapping(uint256 => address) public pools;              // Map to reference Pools corresponding to their respective indices.
    mapping(address => bool)    public isPool;             // True only if a Pool was instantiated by this factory.
    mapping(address => bool)    public poolFactoryAdmins;  // The PoolFactory Admin addresses that have permission to do certain operations in case of disaster management.

    event PoolFactoryAdminSet(address indexed poolFactoryAdmin, bool allowed);

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

    constructor(address _globals) public {
        globals = IMapleGlobals(_globals);
    }

    /**
        @dev   Sets MapleGlobals instance. Only the Governor can call this function.
        @param newGlobals Address of new MapleGlobals.
    */
    function setGlobals(address newGlobals) external {
        _isValidGovernor();
        globals = IMapleGlobals(newGlobals);
    }

    /**
        @dev    Instantiates a Pool.
        @dev    It emits a `PoolCreated` event.
        @param  liquidityAsset The asset escrowed in a LiquidityLocker.
        @param  stakeAsset     The asset escrowed in a StakeLocker.
        @param  slFactory      The factory to instantiate a StakeLocker from.
        @param  llFactory      The factory to instantiate a LiquidityLocker from.
        @param  stakingFee     Fee that Stakers earn on interest, in basis points.
        @param  delegateFee    Fee that the Pool Delegate earns on interest, in basis points.
        @param  liquidityCap   Amount of Liquidity Asset accepted by the Pool.
        @return poolAddress    Address of the instantiated Pool.
    */
    function createPool(
        address liquidityAsset,
        address stakeAsset,
        address slFactory,
        address llFactory,
        uint256 stakingFee,
        uint256 delegateFee,
        uint256 liquidityCap
    ) external whenNotPaused returns (address poolAddress) {
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

    /**
        @dev   Sets a PoolFactory Admin. Only the Governor can call this function.
        @dev   It emits a `PoolFactoryAdminSet` event.
        @param poolFactoryAdmin An address being allowed or disallowed as a PoolFactory Admin.
        @param allowed  Status of a PoolFactory Admin.
    */
    function setPoolFactoryAdmin(address poolFactoryAdmin, bool allowed) external {
        _isValidGovernor();
        poolFactoryAdmins[poolFactoryAdmin] = allowed;
        emit PoolFactoryAdminSet(poolFactoryAdmin, allowed);
    }

    /**
        @dev Triggers paused state. Halts functionality for certain functions. Only the Governor or a PoolFactory Admin can call this function.
    */
    function pause() external {
        _isValidGovernorOrPoolFactoryAdmin();
        super._pause();
    }

    /**
        @dev Triggers unpaused state. Restores functionality for certain functions. Only the Governor or a PoolFactory Admin can call this function.
    */
    function unpause() external {
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
