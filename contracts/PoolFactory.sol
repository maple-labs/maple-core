// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

import "./Pool.sol";

import "./interfaces/IBFactory.sol";

import "./library/TokenUUID.sol";

import "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";

/// @title PoolFactory instantiates Pools.
contract PoolFactory is Pausable {

    uint8 public constant LL_FACTORY = 3;  // Factory type of `LiquidityLockerFactory`
    uint8 public constant SL_FACTORY = 4;  // Factory type of `StakeLockerFactory`

    uint256  public poolsCreated;  // Incrementor for number of Pools created
    IGlobals public globals;       // MapleGlobals contract

    mapping(uint256 => address) public pools;   // Pools address mapping
    mapping(address => bool)    public isPool;  // Used to check if a Pool was instantiated from this contract

    mapping(address => bool) public admins;  // Admin addresses that have permission to do certain operations in case of disaster mgt

    event PoolCreated(
        string  indexed tUUID,
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
        globals = IGlobals(_globals);
    }

    /**
        @dev Update the MapleGlobals contract
        @param newGlobals Address of new MapleGlobals contract
    */
    function setGlobals(address newGlobals) external {
        _isValidGovernor();
        globals = IGlobals(newGlobals);
    }

    /**
        @dev Instantiates a Pool contract.
        @param  liquidityAsset The asset escrowed in LiquidityLocker
        @param  stakeAsset     The asset escrowed in StakeLocker
        @param  slFactory      The factory to instantiate a StakeLocker from
        @param  llFactory      The factory to instantiate a LiquidityLocker from
        @param  stakingFee     Fee that stakers earn on interest, in basis points
        @param  delegateFee    Fee that pool delegate earns on interest, in basis points
        @param  liquidityCap   Amount of liquidityAsset accepted by the pool
    */
    function createPool(
        address liquidityAsset, 
        address stakeAsset,
        address slFactory, 
        address llFactory,
        uint256 stakingFee, 
        uint256 delegateFee,
        uint256 liquidityCap
    ) public whenNotPaused returns (address) {
        _whenProtocolNotPaused();
        {
            IGlobals _globals = globals;
            require(_globals.isValidSubFactory(address(this), llFactory, LL_FACTORY), "PoolFactory:INVALID_LL_FACTORY");
            require(_globals.isValidSubFactory(address(this), slFactory, SL_FACTORY), "PoolFactory:INVALID_SL_FACTORY");
            require(_globals.isValidPoolDelegate(msg.sender),                         "PoolFactory:INVALID_DELEGATE");
            require(IBFactory(_globals.BFactory()).isBPool(stakeAsset),               "PoolFactory:STAKE_ASSET_NOT_BPOOL");
        }
        
        string memory tUUID  = TokenUUID.generateUUID(poolsCreated + 1);
        string memory name   = string(abi.encodePacked("Maple Liquidity Pool Token ", tUUID));
        string memory symbol = string(abi.encodePacked("LP", tUUID));

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

        pools[poolsCreated]   = address(pool);
        isPool[address(pool)] = true;
        poolsCreated++;

        emit PoolCreated(
            tUUID,
            address(pool),
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
        return address(pool);
    }

    /**
        @dev Set admin.
        @param newAdmin New admin address
        @param allowed  Status of an admin
    */
    function setAdmin(address newAdmin, bool allowed) external {
        _isValidGovernor();
        admins[newAdmin] = allowed;
    }

    /**
        @dev Triggers paused state. Halts functionality for certain functions. Only Governor can call this function.
    */
    function pause() external { 
        _isValidGovernorOrAdmin();
        super._pause();
    }

    /**
        @dev Triggers unpaused state. Returns functionality for certain functions. Only Governor can call this function.
    */
    function unpause() external {
        _isValidGovernorOrAdmin();
        super._unpause();
    }

    /**
        @dev Function to determine if msg.sender is eligible to trigger pause/unpause.
    */
    function _isValidGovernor() internal view {
        require(msg.sender == globals.governor(), "PoolFactory:INVALID_GOVERNOR");
    }

    /**
        @dev Function to determine if msg.sender is eligible to trigger pause/unpause.
    */
    function _isValidGovernorOrAdmin() internal {
        require(msg.sender == globals.governor() || admins[msg.sender], "PoolFactory:UNAUTHORIZED");
    }

    /**
        @dev Function to determine if msg.sender is eligible to trigger pause/unpause.
    */
    function _whenProtocolNotPaused() internal {
        require(!globals.protocolPaused(), "PoolFactory:PROTOCOL_PAUSED");
    }
}
