// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;

import "./StakeLocker.sol";

contract StakeLockerFactory {

    mapping(address => address) private owners;    // Mapping of StakeLocker contracts to owners of StakeLockers.
    mapping(address => bool)    private isLocker;  // Mapping for validation of lockers, confirmed when initialized through this contract.

    event StakeLockerCreated(
        address owner,
        address stakeLocker,
        address stakeAsset,
        address liquidityAsset,
        string name,
        string symbol
    );

    /// @notice Creates a new locker.
    /// @param stakeAsset The address of the balancer pool, whose BPTs will be deposited into the stakeLocker.
    /// @param liquidityAsset The address of the dividend token, also the primary investment asset of the LP.
    /// @return The address of the newly created locker.
    //TODO: add a modifier here that only lets a liquidity pool run this. This is good for security, but not critical.
    function newLocker(
        address stakeAsset,
        address liquidityAsset,
        address globals
    ) external returns (address) {
        address stakeLocker   = address(new StakeLocker(stakeAsset, liquidityAsset, msg.sender, globals));
        owners[stakeLocker]   = msg.sender; //address of LP contract that sent it, not poolManagers
        isLocker[stakeLocker] = true;

        emit StakeLockerCreated(
            msg.sender, 
            stakeLocker,
            stakeAsset, 
            liquidityAsset, 
            StakeLocker(stakeLocker).name(), 
            StakeLocker(stakeLocker).symbol()
        );
        return stakeLocker;
    }

    /// @notice Returns the address of the StakeLocker's owner (should be a Pool).
    /// @param locker Address of the StakeLocker.
    /// @return Owner of the StakeLocker.
    function getOwner(address locker) public view returns (address) {
        return owners[locker];
    }

    /// @notice Validates if the provided address is a LiqudityLocker created through this factory.
    /// @param locker Address of the StakeLocker that needs validation.
    /// @return true if locker is a valid StakeLocker.
    function isStakeLocker(address locker) external view returns (bool) {
        return isLocker[locker];
    }
}
