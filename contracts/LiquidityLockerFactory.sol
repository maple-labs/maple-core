// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "./LiquidityLocker.sol";

contract LiquidityLockerFactory {

    mapping(address => address) public owner;     // owner[locker] = Owner of the funding locker.
    mapping(address => bool)    public isLocker;  // True if funding locker was created by this factory, otherwise false.

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
    
}
