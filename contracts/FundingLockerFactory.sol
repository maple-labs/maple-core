// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "./FundingLocker.sol";

import "./interfaces/ILoanFactory.sol";

/// @title FundingLockerFactory instantiates FundingLockers.
contract FundingLockerFactory {

    mapping(address => address) public owner;     // Mapping of locker contract address to its owner i.e owner[locker] = Owner of the funding locker
    mapping(address => bool)    public isLocker;  // True if funding locker was created by this factory, otherwise false

    uint8 public constant factoryType = 2;  // i.e FactoryType::FUNDING_LOCKER_FACTORY

    event FundingLockerCreated(address indexed owner, address fundingLocker, address liquidityAsset);

    /**
        @dev Instantiate a FundingLocker contract.
        @dev It emits a `FundingLockerCreated` event.
        @param liquidityAsset The asset this funding locker will escrow
        @return Address of the instantiated funding locker
    */
    function newLocker(address liquidityAsset) external returns (address) {
        address fundingLocker   = address(new FundingLocker(liquidityAsset, msg.sender));
        owner[fundingLocker]    = msg.sender;
        isLocker[fundingLocker] = true;

        emit FundingLockerCreated(msg.sender, fundingLocker, liquidityAsset);
        return fundingLocker;
    }
}
