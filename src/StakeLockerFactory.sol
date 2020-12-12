// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "./StakeLocker.sol";
import "hardhat/console.sol";

contract StakeLockerFactory {

    // Mapping of StakeLocker contracts to owners of StakeLockers.
    mapping(address => address) private ownerOfLocker;

    // Mapping for validation of lockers, confirmed when initialized through this contract.
    mapping(address => bool) private isLocker;

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
        address _owner = address(msg.sender);
        address _stakeLocker = address(new StakeLocker(_stakeAsset, _liquidityAsset, _owner, _globals));
        ownerOfLocker[_stakeLocker] = _owner; //address of LP contract that sent it, not poolManagers
        isLocker[_stakeLocker] = true;
        return _stakeLocker;
    }

    /// @notice Returns the address of the StakeLocker's owner (should be a LiquidityPool).
    /// @param _locker Address of the StakeLocker.
    /// @return Owner of the StakeLocker.
    function getOwner(address _locker) public view returns (address) {
        return ownerOfLocker[_locker];
    }

    /// @notice Validates if the provided address is a LiqudityLocker created through this factory.
    /// @param _locker Address of the StakeLocker that needs validation.
    /// @return true if _locker is a valid StakeLocker.
    function isStakeLocker(address _locker) external view returns (bool) {
        return isLocker[_locker];
    }

}
