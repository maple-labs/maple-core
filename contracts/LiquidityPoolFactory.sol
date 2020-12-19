// SPDX-License-Identifier: MIT
pragma solidity 0.7.0;

import "./LiquidityPool.sol";
import "./interface/IGlobals.sol";

contract LiquidityPoolFactory {
    // TODO: Consider adjusting LiquidityPools mapping to an array.
    // Mappings for liquidity pool contracts, and their validation.
    mapping(uint256 => address) private _liquidityPools;
    mapping(address => bool) private _isLiquidityPool;

    /// @notice Incrementor for number of LPs created.
    uint256 public liquidityPoolsCreated;

    /// @notice The MapleGlobals.sol contract.
    address public mapleGlobals;

    /// @notice The StakeLockerFactory to use for this LiquidityPoolFactory.
    address public stakeLockerFactory;

    /// @notice The LiquidityLockerFactory to use for this LiquidityPoolFactory.
    address public liquidityLockerFactory;

    constructor(
        address _mapleGlobals,
        address _stakeLockerFactory,
        address _liquidityLockerFactory
    ) {
        mapleGlobals = _mapleGlobals;
        stakeLockerFactory = _stakeLockerFactory;
        liquidityLockerFactory = _liquidityLockerFactory;
    }

    event PoolCreated(
        address indexed _delegate,
        address _liquidityAsset,
        address _stakeAsset,
        uint256 _stakingFeeBasisPoints,
        uint256 _delegateFeeBasisPoints,
        string name,
        string symbol,
        uint256 indexed _id
    );

    /// @notice Instantiates a liquidity pool contract on-chain.
    /// @param _liquidityAsset The primary asset which lenders deposit into the liquidity pool for investment.
    /// @param _stakeAsset The asset which stakers deposit into the liquidity pool for liquidation during defaults.
    /// @param name The name of the liquidity pool's token (minted when investors deposit _liquidityAsset).
    /// @param symbol The ticker of the liquidity pool's token.
    /// @return Address of the instantiated liquidity pool.
    function createLiquidityPool(
        address _liquidityAsset,
        address _stakeAsset,
        uint256 _stakingFeeBasisPoints,
        uint256 _delegateFeeBasisPoints,
        string memory name,
        string memory symbol
    ) public returns (address) {
        require(
            IGlobals(mapleGlobals).validPoolDelegate(msg.sender),
            "LiquidityPoolFactory::createLiquidityPool:ERR_MSG_SENDER_NOT_WHITELISTED"
        );
        LiquidityPool lpool =
            new LiquidityPool(
                _liquidityAsset,
                _stakeAsset,
                stakeLockerFactory,
                liquidityLockerFactory,
                _stakingFeeBasisPoints,
                _delegateFeeBasisPoints,
                name,
                symbol,
                mapleGlobals
            );
        _liquidityPools[liquidityPoolsCreated] = address(lpool);
        _isLiquidityPool[address(lpool)] = true;
        emit PoolCreated(
            msg.sender,
            _liquidityAsset,
            _stakeAsset,
            _stakingFeeBasisPoints,
            _delegateFeeBasisPoints,
            name,
            symbol,
            liquidityPoolsCreated
        );
        liquidityPoolsCreated++;
        return address(lpool);
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
