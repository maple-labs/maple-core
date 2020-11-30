pragma solidity 0.7.0;

import "./LiquidityPool.sol";

contract LiquidityPoolFactory {

    // TODO: Consider adjusting LiquidityPools mapping to an array.
    // Mappings for liquidity pool contracts, and their validation.
    mapping(uint256 => address) private _liquidityPools;
    mapping(address => bool) private _isLiquidityPool;

    /// @notice Incrementor for number of LPs created.
    uint256 public liquidityPoolsCreated;

    /// @notice Instantiates a liquidity pool contract on-chain.
    /// @param _liquidityAsset The primary asset which lenders deposit into the liquidity pool for investment.
    /// @param _stakeAsset The asset which stakers deposit into the liquidity pool for liquidation during defaults.
    /// @param _stakeLockerFactory The factory from which to create the StakeLocker.
    /// @param _liquidityLockerFactory The factory from which to create the LiquidityLocker.
    /// @param name The name of the liquidity pool's token (minted when investors deposit _liquidityAsset).
    /// @param symbol The ticker of the liquidity pool's token.
    /// @param _mapleGlobals Address of the MapleGlobals.sol contract.
    /// @return Address of the instantiated liquidity pool.
    function createLiquidityPool(
        address _liquidityAsset,
        address _stakeAsset,
        address _stakeLockerFactory,
        address _liquidityLockerFactory,
        string memory name,
        string memory symbol,
        address _mapleGlobals
    ) public returns (address) {
        LiquidityPool lpool = new LiquidityPool(
            _liquidityAsset,
            _stakeAsset,
            _stakeLockerFactory,
            _liquidityLockerFactory,
            name,
            symbol,
            _mapleGlobals
        );
        _liquidityPools[liquidityPoolsCreated] = address(lpool);
        _isLiquidityPool[address(lpool)] = true;
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
