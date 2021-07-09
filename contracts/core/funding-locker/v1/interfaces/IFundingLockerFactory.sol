// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { ISubFactory } from "core/subfactory/v1/interfaces/ISubFactory.sol";

/// @title FundingLockerFactory instantiates FundingLockers.
interface IFundingLockerFactory is ISubFactory {

    /**
        @dev   Emits an event indicating a FundingLocker was created.
        @param owner          The owner of the FundingLocker.
        @param fundingLocker  The address of the FundingLocker.
        @param liquidityAsset The Liquidity Asset this FundingLocker will escrow.
     */
    event FundingLockerCreated(address indexed owner, address fundingLocker, address liquidityAsset);

    /**
        @param  fundingLocker The address of a FundingLocker.
        @return The address of the owner of FundingLocker at `fundingLocker`.
     */
    function owner(address fundingLocker) external view returns (address);

    /**
        @param  fundingLocker Some address.
        @return Whether `fundingLocker` is a FundingLocker.
     */
    function isLocker(address fundingLocker) external view returns (bool);

    /**
        @dev The type of the factory (i.e FactoryType::FUNDING_LOCKER_FACTORY).
     */
    function factoryType() external override pure returns (uint8);

    /**
        @dev    Instantiates a FundingLocker. 
        @dev    It emits a `FundingLockerCreated` event. 
        @param  liquidityAsset The Liquidity Asset this FundingLocker will escrow.
        @return fundingLocker  The address of the instantiated FundingLocker.
     */
    function newLocker(address liquidityAsset) external returns (address fundingLocker);

}
