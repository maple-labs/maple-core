// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "./LiquidityPool.sol";
import "./interfaces/IGlobals.sol";
import "./library/TokenUUID.sol";


contract LiquidityPoolFactory {

    uint256 public liquidityPoolsCreated;   // Incrementor for number of LPs created
    address public mapleGlobals;            // The MapleGlobals.sol contract
    address public stakeLockerFactory;      // The StakeLockerFactory to use for this LiquidityPoolFactory
    address public liquidityLockerFactory;  // The LiquidityLockerFactory to use for this LiquidityPoolFactory

    mapping(uint256 => address) private _liquidityPools; // Mappings for liquidity pool contracts, and their validation. (TODO: Consider adjusting LiquidityPools mapping to an array.)
    mapping(address => bool)    private _isLiquidityPool;

    constructor(
        address _mapleGlobals, 
        address _stakeLockerFactory, 
        address _liquidityLockerFactory
    ) public {
        mapleGlobals = _mapleGlobals;
        stakeLockerFactory = _stakeLockerFactory;
        liquidityLockerFactory = _liquidityLockerFactory;
    }

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

    /// @notice Instantiates a liquidity pool contract on-chain.
    /// @param _liquidityAsset The primary asset which lenders deposit into the liquidity pool for investment.
    /// @param _stakeAsset The asset which stakers deposit into the liquidity pool for liquidation during defaults.
    /// @return Address of the instantiated liquidity pool.
    function createLiquidityPool(
        address _liquidityAsset,
        address _stakeAsset,
        uint256 _stakingFee,
        uint256 _delegateFee
    ) public returns (address) {

        require(
            IGlobals(mapleGlobals).validPoolDelegate(msg.sender),
            "LiquidityPoolFactory::createLiquidityPool:ERR_MSG_SENDER_NOT_WHITELISTED"
        );

        string memory tUUID  = TokenUUID.mkUUID(liquidityPoolsCreated + 1);
	    string memory name   = string(abi.encodePacked("Maple Liquidity Pool Token ", tUUID));
        string memory symbol = string(abi.encodePacked("LP", tUUID));

        LiquidityPool lPool =
            new LiquidityPool(
                msg.sender,
                _liquidityAsset,
                _stakeAsset,
                stakeLockerFactory,
                liquidityLockerFactory,
                _stakingFee,
                _delegateFee,
                name,
                symbol,
                mapleGlobals
            );

        _liquidityPools[liquidityPoolsCreated] = address(lPool);
        _isLiquidityPool[address(lPool)]       = true;
        liquidityPoolsCreated++;

        emit PoolCreated(
            tUUID,
            address(lPool),
            msg.sender,
            _liquidityAsset,
            _stakeAsset,
            lPool.liquidityLockerAddress(),
            lPool.stakeLockerAddress(),
            _stakingFee,
            _delegateFee,
            name,
            symbol
        );
        return address(lPool);
    }

    /// @notice Fetch address of a liquidity pool using the ID (incrementor).
    /// @param _id The incrementor value.
    /// @return Address of the liquidity pool at _id.
    function getLiquidityPool(uint256 _id) public view returns (address) {
        return _liquidityPools[_id];
    }

    /// @notice Validate the address, to confirm it's a LiquidityPool.
    /// @param _liquidityPool The address to validate.
    /// @return true if supplied address is valid, otherwise false.
    function isLiquidityPool(address _liquidityPool) public view returns (bool) {
        return _isLiquidityPool[_liquidityPool];
    }
}
