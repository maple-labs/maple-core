// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "./CollateralLocker.sol";
import "./interfaces/ILoanFactory.sol";

contract CollateralLockerFactory {

    mapping(address => address) private owner;     // Mapping of CollateralLocker contracts to the Loan it's attached with.
    mapping(address => bool)    private isLocker;  // Mapping of identification check to confirm a locker was created through this factory

    /// @notice Instantiate a CollateralLocker contract.
    /// @param collateralAsset Address of the collateral asset.
    /// @return Address of the instantiated locker.
    function newLocker(address collateralAsset) external returns (address) {
        address collateralLocker   = address(new CollateralLocker(collateralAsset, msg.sender));
        owner[collateralLocker]    = msg.sender;
        isLocker[collateralLocker] = true;
        return collateralLocker;
    }

    /// @notice Returns the Loan a CollateralLocker is attached with.
    /// @param locker The address of the CollateralLocker contract.
    /// @return The Loan which owns the locker.
    function getOwner(address locker) public view returns (address) {
        return owner[locker];
    }

    /// @notice Confirm if an address is a CollateralLocker instantiated by this factory.
    /// @param locker Address of the locker.
    /// @return True if locker was instantiated by this factory contract, otherwise false.
    function verifyLocker(address locker) external view returns (bool) {
        return isLocker[locker];
    }
}
