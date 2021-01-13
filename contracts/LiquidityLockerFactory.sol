// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "./LiquidityLocker.sol";

contract LiquidityLockerFactory {

    mapping(address => address) public owner;     // owner[locker] = Owner of the liquidity locker.
    mapping(address => bool)    public isLocker;  // True if liquidity locker was created by this factory, otherwise false.

    bytes32 public type = "LiquidityLockerFactory";

    /**
        @dev Instantiate a LiquidityLocker contract.
        @param  liquidityAsset The asset this liquidity locker will escrow.
        @return Address of the instantiated liquidity locker.
    */
    function newLocker(address liquidityAsset) external returns (address) {
        address liquidityLocker   = address(new LiquidityLocker(liquidityAsset, msg.sender));
        owner[liquidityLocker]    = msg.sender;
        isLocker[liquidityLocker] = true;
        return liquidityLocker;
    }
    
}
