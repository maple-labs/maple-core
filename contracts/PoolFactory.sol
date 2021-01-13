// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "./Pool.sol";
import "./interfaces/IBFactory.sol";
import "./library/TokenUUID.sol";

// interface IGlobals {
//     function isValidPoolDelegate(address) external view returns (bool);
//     function getValidSubFactory(address, address, bytes32) external view returns (bool);
// }

contract PoolFactory {

    uint256 public poolsCreated;  // Incrementor for number of LPs created
    address public globals;       // The MapleGlobals.sol contract

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
        globals   = _globals;
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
        
        require(
            IGlobals(globals).getValidSubFactory(address(this), llFactory, bytes32("LiquidityLockerFactory")),
            "LoanFactory::createLoan:ERR_INVALID_LIQUIDITY_LOCKER_FACTORY"
        );
        require(
            IGlobals(globals).getValidSubFactory(address(this), slFactory, bytes32("StakeLockerFactory")),
            "LoanFactory::createLoan:ERR_INVALID_STAKE_LOCKER_FACTORY"
        );
        require(
            IGlobals(globals).isValidPoolDelegate(msg.sender),
            "PoolFactory::createPool:ERR_MSG_SENDER_NOT_WHITELISTED"
        );
        require(
            IBFactory(IGlobals(globals).BFactory()).isBPool(stakeAsset),
            "PoolFactory::createPool:ERR_STAKE_ASSET_NOT_BPOOL"
        );

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
