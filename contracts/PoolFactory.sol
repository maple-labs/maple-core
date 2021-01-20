// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "./Pool.sol";
import "./interfaces/IBFactory.sol";
import "./library/TokenUUID.sol";

contract PoolFactory {

    uint8 public constant LL_FACTORY = 3;   // Factory type of `LiquidityLockerFactory`.
    uint8 public constant SL_FACTORY = 4;   // Factory type of `StakeLockerFactory`.

    uint256  public poolsCreated;       // Incrementor for number of LPs created.
    IGlobals public immutable globals;  // MapleGlobals contract.

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

    constructor(address _globals) public {
        globals   = IGlobals(_globals);
    }

    /**
        @dev Instantiates a Pool contract.
        @param  liquidityAsset The asset escrowed in LiquidityLocker.
        @param  stakeAsset     The asset escrowed in StakeLocker.
        @param  slFactory      The factory to instantiate a Stake Locker from.
        @param  llFactory      The factory to instantiate a Liquidity Locker from.
        @param  stakingFee     Fee that stakers earn on interest, in bips.
        @param  delegateFee    Fee that pool delegate earns on interest, in bips.
    */
    function createPool(
        address liquidityAsset, 
        address stakeAsset,
        address slFactory, 
        address llFactory,
        uint256 stakingFee, 
        uint256 delegateFee
    ) public returns (address) {
        
        require(globals.isValidSubFactory(address(this), llFactory, LL_FACTORY), "PoolFactory:INVALID_LL_FACTORY");
        require(globals.isValidSubFactory(address(this), slFactory, SL_FACTORY), "PoolFactory:INVALID_SL_FACTORY");
        require(globals.isValidPoolDelegate(msg.sender),                         "PoolFactory:MSG_SENDER_NOT_WHITELISTED");
        require(IBFactory(globals.BFactory()).isBPool(stakeAsset),               "PoolFactory:STAKE_ASSET_NOT_BPOOL");

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
                name,
                symbol,
                address(globals)
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
