pragma solidity 0.7.0;
import "./liquidAssetLocker.sol";

contract liquidAssetLockerFactory {
	// Mapping data structure for staked asset lockers.
	mapping(uint256 => address) private lockers;

	// Mapping data structure for owners of staked asset lockers.
	mapping(address => address) private lockerPool;

	uint256 public lockersCreated;

	/// @notice Creates a new locker.
	/// @param _liquidAsset The address of the dividend token, also the primary investment asset of the LP.
	/// @return The address of the newly created locker.
	// TODO: Consider whether this needs to be external or public.
	function newLocker(address _liquidAsset) external returns (address) {
		address _LPaddy = address(msg.sender);
		address _liquidLocker = address(
			new liquidAssetLocker(_liquidAsset, _LPaddy)
		);
		lockers[lockersCreated] = _liquidLocker;
		lockerPool[_liquidLocker] = _LPaddy;
		lockersCreated++;
		return _liquidLocker;
	}

	/// @notice Returns the address of the locker, using incrementor value to search.
	/// @param _id The incrementor value to search with.
	/// @return The address of the locker.
	function getLocker(uint256 _id) public view returns (address) {
		return lockers[_id];
	}

	/// @notice Returns the address of the locker's parent liquidity pool.
	/// @param _locker The address of the locker.
	/// @return The owner of the locker.
	function getPool(address _locker) public view returns (address) {
		return lockerPool[_locker];
	}
}
