// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "./Pool.sol";

import "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";

/// @title PoolFactory instantiates Pools.
contract PoolFactory is Pausable {

    uint8 public constant LL_FACTORY = 3;  // Factory type of `LiquidityLockerFactory`
    uint8 public constant SL_FACTORY = 4;  // Factory type of `StakeLockerFactory`

    uint256  public poolsCreated;  // Incrementor for number of Pools created
    IGlobals public globals;       // MapleGlobals contract

    mapping(uint256 => address) public pools;   // Map to keep `Pool` contract corresponds to its index.
    mapping(address => bool)    public isPool;  // Used to check if a `Pool` was instantiated from this factory.
    mapping(address => bool)    public admins;  // Admin addresses that have permission to do certain operations in case of disaster mgt

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
        globals = IGlobals(_globals);
    }

    /**
        @dev Update the MapleGlobals contract. Only the Governor can call this function.
        @param newGlobals Address of new MapleGlobals contract
    */
    function setGlobals(address newGlobals) external {
        _isValidGovernor();
        globals = IGlobals(newGlobals);
    }

    /**
        @dev Instantiates a Pool contract.
        @dev It emits a `PoolCreated` event.
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
            require(_globals.isValidSubFactory(address(this), llFactory, LL_FACTORY), "PF:INVALID_LL_FACTORY");
            require(_globals.isValidSubFactory(address(this), slFactory, SL_FACTORY), "PF:INVALID_SL_FACTORY");
            require(_globals.isValidPoolDelegate(msg.sender),                         "PF:NOT_DELEGATE");
        }

        string memory name   = string(abi.encodePacked("Maple Pool Token"));
        string memory symbol = string(abi.encodePacked("MPL-LP"));

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
        @dev Set admin. Only the Governor can call this function.
        @param newAdmin New admin address
        @param allowed  Status of an admin
    */
    function setAdmin(address newAdmin, bool allowed) external {
        _isValidGovernor();
        admins[newAdmin] = allowed;
    }

    /**
        @dev Triggers paused state. Halts functionality for certain functions. Only the Governor or a Pool Factory Admin can call this function.
    */
    function pause() external {
        _isValidGovernorOrAdmin();
        super._pause();
    }

    /**
        @dev Triggers unpaused state. Returns functionality for certain functions. Only the Governor or a Pool Factory Admin can call this function.
    */
    function unpause() external {
        _isValidGovernorOrAdmin();
        super._unpause();
    }

    /**
        @dev Checks that msg.sender is the Governor.
    */
    function _isValidGovernor() internal view {
        require(msg.sender == globals.governor(), "PF:NOT_GOV");
    }

    /**
        @dev Checks that msg.sender is the Governor or a Pool Factory Admin.
    */
    function _isValidGovernorOrAdmin() internal {
        require(msg.sender == globals.governor() || admins[msg.sender], "PF:NOT_GOV_OR_ADMIN");
    }

    /**
        @dev Function to determine if protocol is paused/unpaused.
    */
    function _whenProtocolNotPaused() internal {
        require(!globals.protocolPaused(), "PF:PROTOCOL_PAUSED");
    }
}
