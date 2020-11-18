pragma solidity 0.7.0;

import "./LoanVaultFundingLocker.sol";

contract LoanVaultFundingLockerFactory {

    // Mapping of LoanVaultFundingLocker contracts to the LoanVault it's attached with.
    mapping(address => address) private lockerOwner;

    // Mapping of identification check to confirm a locker was created through this factory.
    mapping(address => bool) private isLocker;

    /// @notice Instantiate a LoanVaultFundingLocker contract.
    /// @param _fundingAsset Address of the funding asset.
    /// @return Address of the instantiated locker.
    function newLocker(address _fundingAsset) public returns (address) {
      address _fundingLocker = address(new LoanVaultFundingLocker(_fundingAsset, msg.sender));
      lockerOwner[_fundingLocker] = msg.sender;
      isLocker[_fundingLocker] = true;
      return _fundingLocker;
    }

    /// @notice Returns the LoanVault a LoanVaultFundingLocker is attached with.
    /// @param _locker The address of the LoanVaultFundingLocker contract.
    /// @return The LoanVault which owns the locker.
    function getOwner(address _locker) public view returns (address) {
        return lockerOwner[_locker];
    }

    /// @notice Confirm if an address is a LoanVaultFundingLocker instantiated by this factory.
    /// @param _locker Address of the locker.
    /// @return True if _locker was instantiated by this factory contract, otherwise false.
    function verifyLocker(address _locker) external view returns (bool) {
        return isLocker[_locker];
    }
}
