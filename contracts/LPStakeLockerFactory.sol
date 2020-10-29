// SPDX-License-Identifier: MIT

pragma solidity 0.7.0;

import "./LP/LPStakeLocker.sol";

contract LPStakeLockerFactory {

    mapping(uint256 => address) lockers;
    uint256 public lockersCreated;

    event NewLocker(address newLocker);

    function newLocker(address _stakedAsset) public returns (address) {
        address locker = address(new LPStakeLocker(
            _stakedAsset,
            'NAME',
            'SYMBOL',
            IERC20(_stakedAsset)
        ));
        lockers[lockersCreated] = address(locker);
        lockersCreated++;
        emit NewLocker(locker);
        return address(locker);
    }

}
