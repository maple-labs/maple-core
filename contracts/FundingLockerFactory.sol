// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "./FundingLocker.sol";
import "./interfaces/ILoanVaultFactory.sol";

contract FundingLockerFactory {

    mapping(address => address) private lockerOwner;     // Mapping of FundingLocker contracts to the LoanVault it's attached with.
    mapping(address => bool)    private isLocker;        // Mapping of identification check to confirm a locker was created through this factory.
    mapping(address => bool)    private deployedLocker;  // Unique deployment per address, ensure no duplication (or decoupling).

    /// @notice Instantiate a FundingLocker contract.
    /// @param _fundingAsset Address of the funding asset.
    /// @return Address of the instantiated locker.
    function newLocker(address _fundingAsset) public returns (address) {
        require(
            !deployedLocker[msg.sender], 
            "FundingLockerFactory::newLocker:ERR_MSG_SENDER_ALREADY_DEPLOYED_FUNDING_LOCKER"
        );
        deployedLocker[msg.sender] = true;
        address _fundingLocker = address(new FundingLocker(_fundingAsset, msg.sender));
        lockerOwner[_fundingLocker] = msg.sender;
        isLocker[_fundingLocker] = true;
        return _fundingLocker;
    }

    /// @notice Returns the LoanVault a FundingLocker is attached with.
    /// @param _locker The address of the FundingLocker contract.
    /// @return The LoanVault which owns the locker.
    function getOwner(address _locker) public view returns (address) {
        return lockerOwner[_locker];
    }

    /// @notice Confirm if an address is a FundingLocker instantiated by this factory.
    /// @param _locker Address of the locker.
    /// @return True if _locker was instantiated by this factory contract, otherwise false.
    function verifyLocker(address _locker) external view returns (bool) {
        return isLocker[_locker];
    }
}
