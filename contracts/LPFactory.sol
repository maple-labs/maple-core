pragma solidity 0.7.0;

import "./LP.sol";

contract LPFactory {
	// Mapping data structure for all liquidity pools.
	mapping(uint256 => address) private LiquidityPools;
	mapping(address => bool) private _isLPool;
	/// @notice Incrementor for number of LPs created.
	uint256 public LiquidityPoolsCreated;

	/// @notice Instantiates a liquidity pool contract on-chain.
	/// @param _liquidAsset The primary asset which lenders deposit into the liquidity pool for investment.
	/// @param _stakedAsset The asset which stakers deposit into the liquidity pool for liquidation during defaults.
	/// @param _stakedAssetLockerFactory The factory from which to create the Staked Asset locker.
	/// @param name The name of the liquidity pool's token (minted when investors deposit _liquidAsset).
	/// @param symbol The ticker of the liquidity pool's token.
	/// @param _mapleGlobals Address of the MapleGlobals.sol contract.
	/// @return The address of the newly instantiated liquidity pool.
	function createLiquidityPool(
		address _liquidAsset,
		address _stakedAsset,
		address _stakedAssetLockerFactory,
		address _liquidAssetLockerFactory,
		string memory name,
		string memory symbol,
		address _mapleGlobals
	) public returns (address) {
		LP lpool = new LP(
			_liquidAsset,
			_stakedAsset,
			_stakedAssetLockerFactory,
			_liquidAssetLockerFactory,
			name,
			symbol,
			_mapleGlobals
		);
		LiquidityPools[LiquidityPoolsCreated] = address(lpool);
		_isLPool[address(lpool)] = true;
		LiquidityPoolsCreated++;
		return address(lpool);
	}

	/// @dev Fetch the address of a liquidity pool using the id (incrementor).
	/// @param _id The incrementor value to supply.
	/// @return The address of the liquidity pool at _id.
	function getLiquidityPool(uint256 _id) public view returns (address) {
		return LiquidityPools[_id];
	}

	function isLPool(address _addy) public view returns (bool) {
		return _isLPool[_addy];
	}
}
