// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "./FundingLocker.sol";
import "./interfaces/ILoanFactory.sol";

contract FundingLockerFactory {

    mapping(address => address) private owner;     // Mapping of FundingLocker contracts to the Loan it's attached with.
    mapping(address => bool)    private isLocker;  // Mapping of identification check to confirm a locker was created through this factory.

    /// @notice Instantiate a FundingLocker contract.
    /// @param loanAsset Address of the funding asset.
    /// @return Address of the instantiated locker.
    function newLocker(address loanAsset) public returns (address) {
        address fundingLocker   = address(new FundingLocker(loanAsset, msg.sender));
        owner[fundingLocker]    = msg.sender;
        isLocker[fundingLocker] = true;
        return fundingLocker;
    }

    /// @notice Returns the Loan a FundingLocker is attached with.
    /// @param locker The address of the FundingLocker contract.
    /// @return The Loan which owns the locker.
    function getOwner(address locker) public view returns (address) {
        return owner[locker];
    }

    /// @notice Confirm if an address is a FundingLocker instantiated by this factory.
    /// @param locker Address of the locker.
    /// @return True if locker was instantiated by this factory contract, otherwise false.
    function verifyLocker(address locker) external view returns (bool) {
        return isLocker[locker];
    }
}
