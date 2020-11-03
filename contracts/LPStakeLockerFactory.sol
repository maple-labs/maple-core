// SPDX-License-Identifier: MIT

pragma solidity 0.7.0;

import "./LPStakeLocker.sol";

contract LPStakeLockerFactory {
    // Mapping data structure for staked asset lockers.
    mapping(uint256 => address) private lockers;

    // Mapping data structure for owners of staked asset lockers.
    mapping(address => address) private lockerPool;

    /// @notice Incrementor for number of lockers created.
    uint256 public lockersCreated;

    /// @notice Fires when a new locker is instantiated.
    /// @param newLocker The address of a newly instantiated locker.
    event NewLocker(address newLocker);

    /// @notice Creates a new locker.
    /// @param _stakedAsset The address of the balancer pool, whose BPTs will be deposited into the stakeLocker.
    /// @param _liquidAsset The address of the dividend token, also the primary investment asset of the LP.
    /// @return The address of the newly created locker.
    // TODO: Consider whether this needs to be external or public.
    function newLocker(address _stakedAsset, address _liquidAsset)
        external
        returns (address)
    {
        address locker = address(new LPStakeLocker(_stakedAsset, _liquidAsset));
        lockers[lockersCreated] = address(locker);
        lockerPool[address(locker)] = address(msg.sender); //address of LP contract that sent it, not poolManager
        lockersCreated++;
        emit NewLocker(locker);
        return address(locker);
    }

    /// @notice Returns the address of the locker's owner.
    /// @param _locker The address of the locker.
    /// @return The owner of the locker.
    function getPool(address _locker) public view returns (address) {
        return lockerPool[_locker];
    }

    /// @notice Returns the address of the locker, using incrementor value to search.
    /// @param _id The incrementor value to search with.
    /// @return The address of the locker.
    function getLocker(uint256 _id) public view returns (address) {
        return lockers[_id];
    }
}
