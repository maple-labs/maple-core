// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "./FundingLocker.sol";
import "./interfaces/ILoanFactory.sol";

contract FundingLockerFactory {

    mapping(address => address) public owner;     // owner[locker] = Owner of the funding locker.
    mapping(address => bool)    public isLocker;  // True if funding locker was created by this factory, otherwise false.

    uint8 public constant factoryType = 2;        // i.e LockerFactoryTypes::FUNDING_LOCKER_FACTORY.

    /**
        @dev Instantiate a FundingLocker contract.
        @param  loanAsset The asset this funding locker will escrow.
        @return Address of the instantiated funding locker.
    */
    function newLocker(address loanAsset) public returns (address) {
        address fundingLocker   = address(new FundingLocker(loanAsset, msg.sender));
        owner[fundingLocker]    = msg.sender;
        isLocker[fundingLocker] = true;
        return fundingLocker;
    }
    
}
