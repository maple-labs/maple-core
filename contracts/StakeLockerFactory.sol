// SPDX-License-Identifier: MIT
// SPDX-License-Identifier: MIT

pragma solidity 0.7.0;

import "./StakeLocker.sol";

contract StakeLockerFactory {
    // Mapping data structure for owners of staked asset lockers.
    mapping(address => address) private lockerPool;

    // @notice Creates a new locker.
    // @param _stakeAsset The address of the balancer pool, whose BPTs will be deposited into the stakeLocker.
    // @param _liquidityAsset The address of the dividend token, also the primary investment asset of the LP.
    // @return The address of the newly created locker.
    //TODO: add a modifier here that only lets a liquidity pool run this. This is good for security, but not critical.
    function newLocker(
        address _stakeAsset,
        address _liquidityAsset,
        address _globals
    ) external returns (address) {
        address _ownerLP = address(msg.sender);
        address locker = address(new StakeLocker(_stakeAsset, _liquidityAsset, _ownerLP, _globals));
        lockerPool[address(locker)] = _ownerLP; //address of LP contract that sent it, not poolManager
        return address(locker);
    }

    // @notice Returns the address of the locker's parent liquidity pool.
    // @param _locker The address of the locker.
    // @return The owner of the locker.
    function getPool(address _locker) public view returns (address) {
        return lockerPool[_locker];
    }
}
