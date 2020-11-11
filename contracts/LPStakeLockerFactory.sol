// SPDX-License-Identifier: MIT

pragma solidity 0.7.0;

import "./LPStakeLocker.sol";

contract LPStakeLockerFactory {
    // Mapping data structure for owners of staked asset lockers.
    mapping(address => address) private lockerPool;

    // @notice Creates a new locker.
    // @param _stakedAsset The address of the balancer pool, whose BPTs will be deposited into the stakeLocker.
    // @param _liquidAsset The address of the dividend token, also the primary investment asset of the LP.
    // @return The address of the newly created locker.
    // TODO: Consider whether this needs to be external or public.
    function newLocker(address _stakedAsset, address _liquidAsset) external returns (address) {
        address locker = address(new LPStakeLocker(_stakedAsset, _liquidAsset));
        lockerPool[address(locker)] = address(msg.sender); //address of LP contract that sent it, not poolManager
        return address(locker);
    }

    // @notice Returns the address of the locker's parent liquidity pool.
    // @param _locker The address of the locker.
    // @return The owner of the locker.
    function getPool(address _locker) public view returns (address) {
        return lockerPool[_locker];
    }
}
