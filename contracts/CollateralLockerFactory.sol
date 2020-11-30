pragma solidity 0.7.0;

import "./CollateralLocker.sol";
import "./interface/ILoanVaultFactory.sol";

contract CollateralLockerFactory {

    // Mapping of CollateralLocker contracts to the LoanVault it's attached with.
    mapping(address => address) private lockerOwner;

    // Mapping of identification check to confirm a locker was created through this factory.
    mapping(address => bool) private isLocker;

    // Unique deployment per address, ensure no duplication (or decoupling).
    mapping(address => bool) private deployedLocker;

    /// @notice Instantiate a CollateralLocker contract.
    /// @param _collateralAsset Address of the collateral asset.
    /// @return Address of the instantiated locker.
    function newLocker(address _collateralAsset) external returns (address) {
        require(
            !deployedLocker[msg.sender], 
            "CollateralLockerFactory::newLocker:ERR_MSG_SENDER_ALREADY_DEPLOYED_FUNDING_LOCKER"
        );
        deployedLocker[msg.sender] = true;
        address _collateralLocker = address(new CollateralLocker(_collateralAsset, msg.sender));
        lockerOwner[_collateralLocker] = msg.sender;
        isLocker[_collateralLocker] = true;
        return _collateralLocker;
    }

    /// @notice Returns the LoanVault a CollateralLocker is attached with.
    /// @param _locker The address of the CollateralLocker contract.
    /// @return The LoanVault which owns the locker.
    function getOwner(address _locker) public view returns (address) {
        return lockerOwner[_locker];
    }

    /// @notice Confirm if an address is a CollateralLocker instantiated by this factory.
    /// @param _locker Address of the locker.
    /// @return True if _locker was instantiated by this factory contract, otherwise false.
    function verifyLocker(address _locker) external view returns (bool) {
        return isLocker[_locker];
    }
}
