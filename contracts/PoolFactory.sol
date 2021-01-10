// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "./Pool.sol";
import "./interfaces/IGlobals.sol";
import "./library/TokenUUID.sol";


contract PoolFactory {

    uint256 public poolsCreated;  // Incrementor for number of LPs created
    address public globals;       // The MapleGlobals.sol contract
    address public slFactory;     // The StakeLockerFactory to use for this PoolFactory
    address public llFactory;     // The LiquidityLockerFactory to use for this PoolFactory

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
        string  name,
        string  symbol
    );

    constructor(address _globals, address _slFactory, address _llFactory) public {
        globals   = _globals;
        slFactory = _slFactory;
        llFactory = _llFactory;
    }

    /**
        @notice Instantiates a Pool contract.
        @param  liquidityAsset The asset escrowed in LiquidityLocker.
        @param  stakeAsset     The asset escrowed in StakeLocker.
        @param  stakingFee     Fee that stakers earn.
        @param  delegateFee    Fee that pool delegate earns.
    */
    function createPool(address liquidityAsset, address stakeAsset, uint256 stakingFee, uint256 delegateFee) public returns (address) {
        
        require(
            IGlobals(globals).isValidPoolDelegate(msg.sender),
            "PoolFactory::createPool:ERR_MSG_SENDER_NOT_WHITELISTED"
        );

        string memory tUUID  = TokenUUID.generatedUUID(poolsCreated + 1);
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
                name,
                symbol,
                globals
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
            name,
            symbol
        );
        return address(pool);
    }
    
}
