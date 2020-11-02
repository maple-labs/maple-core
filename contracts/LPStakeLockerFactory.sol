// SPDX-License-Identifier: MIT

pragma solidity 0.7.0;

import "./LP/LPStakeLocker.sol";

contract LPStakeLockerFactory {
    mapping(uint256 => address) private lockers;
    mapping(address => address) private lockerOwner;
    uint256 public lockersCreated;

    event NewLocker(address newLocker);

    function newLocker(
        address _stakedAsset,
        address _liquidAsset //should be external? only callable by other contracts?
    ) external returns (address) {
        address locker = address(
            new LPStakeLocker(
                _stakedAsset,
                _liquidAsset
            )
        );
        lockers[lockersCreated] = address(locker);
        lockerOwner[address(locker)] = address(msg.sender);
        lockersCreated++;
        emit NewLocker(locker);
        return address(locker);
    }

    function getOwner(address _locker) public view returns (address) {
        return lockerOwner[_locker];
    }

    function getLocker(uint256 _ind) public view returns (address) {
        return lockers[_ind];
    }
}
