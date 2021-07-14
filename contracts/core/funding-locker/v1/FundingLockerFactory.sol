// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { FundingLocker } from "./FundingLocker.sol";

import { IFundingLockerFactory } from "./interfaces/IFundingLockerFactory.sol";

/// @title FundingLockerFactory instantiates FundingLockers.
contract FundingLockerFactory is IFundingLockerFactory {

    mapping(address => address) public override owner;     // Owners of respective FundingLockers.
    mapping(address => bool)    public override isLocker;  // True only if a FundingLocker was created by this factory.

    uint8 public override constant factoryType = 2;

    function newLocker(address liquidityAsset) external override returns (address fundingLocker) {
        fundingLocker           = address(new FundingLocker(liquidityAsset, msg.sender));
        owner[fundingLocker]    = msg.sender;
        isLocker[fundingLocker] = true;

        emit FundingLockerCreated(msg.sender, fundingLocker, liquidityAsset);
    }

}
