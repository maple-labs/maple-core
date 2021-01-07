// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "./LiquidityLocker.sol";

contract LiquidityLockerFactory {

    mapping(address => address) private owner;     // Mapping of LiquidityLocker contracts to owners of LiquidityLockers.
    mapping(address => bool)    private isLocker;  // Mapping for validation of lockers, confirmed when initialized through this contract.

    // TODO: Consider whether this needs to be external or public.
    // TODO: ADD MODIFIER LETTING ONLY LIQUIDITY POOLS RUN THIS (not critical, but good)
    /// @notice Creates a new LiquidityLocker.
    /// @param liquidityAsset Address of the LiquidityAsset for the Pool.
    /// @return Address of the new LiquidityLocker.
    function newLocker(address liquidityAsset) external returns (address) {
        address liquidityLocker   = address(new LiquidityLocker(liquidityAsset, msg.sender));
        owner[liquidityLocker]    = msg.sender;
        isLocker[liquidityLocker] = true;
        return liquidityLocker;
    }

    /// @notice Returns the address of the LiquidityLocker's owner (should be a Pool).
    /// @param locker Address of the LiquidityLocker.
    /// @return Owner of the LiquidityLocker.
    function getOwner(address locker) public view returns (address) {
        return owner[locker];
    }

    /// @notice Validates if the provided address is a LiqudityLocker created through this factory.
    /// @param locker Address of the LiquidityLocker that needs validation.
    /// @return true if locker is a valid LiquidityLocker.
    function isLiquidityLocker(address locker) external view returns (bool) {
        return isLocker[locker];
    }
}
