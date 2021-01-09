// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "./CollateralLocker.sol";
import "./interfaces/ILoanFactory.sol";

contract CollateralLockerFactory {

    mapping(address => address) public owner;     // owner[locker] = Owner of the collateral locker.
    mapping(address => bool)    public isLocker;  // True if collateral locker was created by this factory, otherwise false.

    /**
        @notice Instantiate a CollateralLocker contract.
        @param  collateralAsset Address of the collateral asset.
        @return Address of the instantiated locker.
    */
    function newLocker(address collateralAsset) external returns (address) {
        address collateralLocker   = address(new CollateralLocker(collateralAsset, msg.sender));
        owner[collateralLocker]    = msg.sender;
        isLocker[collateralLocker] = true;
        return collateralLocker;
    }
    
}
