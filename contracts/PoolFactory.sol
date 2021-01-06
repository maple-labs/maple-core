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

    mapping(uint256 => address) private pools;  // Mappings for liquidity pool contracts, and their validation. (TODO: Consider adjusting Pools mapping to an array.)
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

    /// @notice Instantiates a liquidity pool contract on-chain.
    /// @param liquidityAsset The primary asset which lenders deposit into the liquidity pool for investment.
    /// @param stakeAsset The asset which stakers deposit into the liquidity pool for liquidation during defaults.
    /// @return Address of the instantiated liquidity pool.
    function createPool(address liquidityAsset, address stakeAsset, uint256 stakingFee, uint256 delegateFee) public returns (address) {
        
        require(
            IGlobals(globals).validPoolDelegate(msg.sender),
            "PoolFactory::createPool:ERR_MSG_SENDER_NOT_WHITELISTED"
        );

        string memory tUUID  = TokenUUID.mkUUID(poolsCreated + 1);
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

    /// @notice Fetch address of a liquidity pool using the ID (incrementor).
    /// @param id The incrementor value.
    /// @return Address of the liquidity pool at id.
    function getPool(uint256 id) public view returns (address) {
        return pools[id];
    }
}
