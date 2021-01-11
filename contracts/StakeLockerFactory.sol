// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;

import "./StakeLocker.sol";

contract StakeLockerFactory {

    mapping(address => address) public owner;     // owner[locker] = Owner of the stake locker.
    mapping(address => bool)    public isLocker;  // True if stake locker was created by this factory, otherwise false.

    event StakeLockerCreated(
        address owner,
        address stakeLocker,
        address stakeAsset,
        address liquidityAsset,
        string name,
        string symbol
    );

    /**
        @dev Instantiate a StakeLocker contract.
        @return Address of the instantiated stake locker.
        @param stakeAsset     Address of the stakeAsset (generally a balancer pool).
        @param liquidityAsset Address of the liquidityAsset (as defined in the pool).
        @param globals        Address of the MapleGlobals contract.
    */
    function newLocker(
        address stakeAsset,
        address liquidityAsset,
        address globals
    ) external returns (address) {
        address stakeLocker   = address(new StakeLocker(stakeAsset, liquidityAsset, msg.sender, globals));
        owner[stakeLocker]    = msg.sender;
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
    
}
