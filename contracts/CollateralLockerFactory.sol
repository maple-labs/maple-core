// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

import "./CollateralLocker.sol";

import "./interfaces/ILoanFactory.sol";

contract CollateralLockerFactory {

    mapping(address => address) public owner;     // owner[locker] = Owner of the collateral locker.
    mapping(address => bool)    public isLocker;  // True if collateral locker was created by this factory, otherwise false.

    uint8 public constant factoryType = 0;        // i.e FactoryType::COLLATERAL_LOCKER_FACTORY.

    /**
        @dev Instantiate a CollateralLocker contract.
        @param  collateralAsset The asset this collateral locker will escrow.
        @return Address of the instantiated collateral locker.
    */
    function newLocker(address collateralAsset) external returns (address) {
        address collateralLocker   = address(new CollateralLocker(collateralAsset, msg.sender));
        owner[collateralLocker]    = msg.sender;
        isLocker[collateralLocker] = true;
        return collateralLocker;
    }
}
