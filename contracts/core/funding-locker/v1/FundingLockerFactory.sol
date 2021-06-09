// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "./FundingLocker.sol";

/// @title FundingLockerFactory instantiates FundingLockers.
contract FundingLockerFactory {

    mapping(address => address) public owner;     // Owners of respective FundingLockers.
    mapping(address => bool)    public isLocker;  // True only if a FundingLocker was created by this factory.

    uint8 public constant factoryType = 2;

    event FundingLockerCreated(address indexed owner, address fundingLocker, address liquidityAsset);

    function newLocker(address liquidityAsset) external returns (address fundingLocker) {
        fundingLocker           = address(new FundingLocker(liquidityAsset, msg.sender));
        owner[fundingLocker]    = msg.sender;
        isLocker[fundingLocker] = true;

        emit FundingLockerCreated(msg.sender, fundingLocker, liquidityAsset);
    }

}
