// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "./Pool.sol";

import "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";

/// @title PoolFactory instantiates Pools.
contract PoolFactory is Pausable {

    uint8 public constant LL_FACTORY = 3;  // Factory type of `LiquidityLockerFactory`
    uint8 public constant SL_FACTORY = 4;  // Factory type of `StakeLockerFactory`

    uint256  public poolsCreated;  // Incrementor for number of Pools created
    IMapleGlobals public globals;  // MapleGlobals contract

    mapping(uint256 => address) public pools;              // Map to keep `Pool` contract corresponds to its index.
    mapping(address => bool)    public isPool;             // Used to check if a `Pool` was instantiated from this factory.
    mapping(address => bool)    public poolFactoryAdmins;  // Pool Factory Admin addresses that have permission to do certain operations in case of disaster mgt

    event PoolFactoryAdminSet(address poolFactoryAdmin, bool allowed);

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
        @dev   Update the MapleGlobals contract. Only the Governor can call this function.
        @param newGlobals Address of new MapleGlobals contract.
    */
    function setGlobals(address newGlobals) external {
        _isValidGovernor();
        globals = IMapleGlobals(newGlobals);
    }

    /**
        @dev    Instantiates a Pool contract.
        @dev    It emits a `PoolCreated` event.
        @param  liquidityAsset The asset escrowed in LiquidityLocker.
        @param  stakeAsset     The asset escrowed in StakeLocker.
        @param  slFactory      The factory to instantiate a StakeLocker from.
        @param  llFactory      The factory to instantiate a LiquidityLocker from.
        @param  stakingFee     Fee that stakers earn on interest, in basis points.
        @param  delegateFee    Fee that pool delegate earns on interest, in basis points.
        @param  liquidityCap   Amount of liquidityAsset accepted by the pool.
        @return poolAddress    Address of the instantiated pool.
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
        @dev   Set pool factory admin. Only the Governor can call this function.
        @dev   It emits a `PoolFactoryAdminSet` event.
        @param poolFactoryAdmin An address being allowed or disallowed as a Pool Factory Admin.
        @param allowed  Status of a pool factory admin.
    */
    function setPoolFactoryAdmin(address poolFactoryAdmin, bool allowed) external {
        _isValidGovernor();
        poolFactoryAdmins[poolFactoryAdmin] = allowed;
        emit PoolFactoryAdminSet(poolFactoryAdmin, allowed);
    }

    /**
        @dev Triggers paused state. Halts functionality for certain functions. Only the Governor or a Pool Factory Admin can call this function.
    */
    function pause() external {
        _isValidGovernorOrPoolFactoryAdmin();
        super._pause();
    }

    /**
        @dev Triggers unpaused state. Returns functionality for certain functions. Only the Governor or a Pool Factory Admin can call this function.
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
        @dev Checks that `msg.sender` is the Governor or a Pool Factory Admin.
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
