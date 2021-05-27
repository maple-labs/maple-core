// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "./FundingLocker.sol";

import "./interfaces/ILoanFactory.sol";

/// @title FundingLockerFactory instantiates FundingLockers.
contract FundingLockerFactory {

    mapping(address => address) public owner;     // Mapping of FundingLocker addresses to their owner (i.e owner[locker] = Owner of the FundingLocker).
    mapping(address => bool)    public isLocker;  // True only if a FundingLocker was created by this factory.

    uint8 public constant factoryType = 2;  // i.e FactoryType::FUNDING_LOCKER_FACTORY

    event FundingLockerCreated(address indexed owner, address fundingLocker, address liquidityAsset);

    /**
        @dev    Instantiates a FundingLocker.
        @dev    It emits a `FundingLockerCreated` event.
        @param  liquidityAsset The Liquidity Asset this FundingLocker will escrow.
        @return fundingLocker  Address of the instantiated FundingLocker.
    */
    function newLocker(address liquidityAsset) external returns (address fundingLocker) {
        fundingLocker           = address(new FundingLocker(liquidityAsset, msg.sender));
        owner[fundingLocker]    = msg.sender;
        isLocker[fundingLocker] = true;

        emit FundingLockerCreated(msg.sender, fundingLocker, liquidityAsset);
    }

}
