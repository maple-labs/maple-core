// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "./Pool.sol";

import "./interfaces/IBFactory.sol";

import "./library/TokenUUID.sol";

import "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";

contract PoolFactory is Pausable {

    uint8 public constant LL_FACTORY = 3;   // Factory type of `LiquidityLockerFactory`.
    uint8 public constant SL_FACTORY = 4;   // Factory type of `StakeLockerFactory`.

    uint256  public poolsCreated;  // Incrementor for number of LPs created.
    IGlobals public globals;       // MapleGlobals contract.

    mapping(uint256 => address) public pools;  // Mappings for liquidity pool contracts, and their validation.
    mapping(address => bool)    public isPool;

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
        @dev Update the maple globals contract
        @param  newGlobals Address of new maple globals contract
    */
    function setGlobals(address newGlobals) external {
        _isValidGovernor();
        globals = IGlobals(newGlobals);
    }

    /**
        @dev Instantiates a Pool contract.
        @param  liquidityAsset The asset escrowed in LiquidityLocker.
        @param  stakeAsset     The asset escrowed in StakeLocker.
        @param  slFactory      The factory to instantiate a Stake Locker from.
        @param  llFactory      The factory to instantiate a Liquidity Locker from.
        @param  stakingFee     Fee that stakers earn on interest, in bips.
        @param  delegateFee    Fee that pool delegate earns on interest, in bips.
        @param  liquidityCap   Amount of liquidity tokens accepted by the pool.
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
            // TODO: Do we need to validate isValidPoolFactory here? Its not being used anywhere currently
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
        @dev Triggers stopped state.
             The contract must not be paused.
    */
    function pause() external { 
        _isValidGovernor();
        super._pause();
    }

    /**
        @dev Returns to normal state.
             The contract must be paused.
    */
    function unpause() external {
        _isValidGovernor();
        super._unpause();
    }

    function _isValidGovernor() internal view {
        require(msg.sender == globals.governor(), "PF:INVALID_GOVERNOR");
    }

    function _whenProtocolNotPaused() internal {
        require(!globals.protocolPaused(), "PF:PROTOCOL_PAUSED");
    }
}
