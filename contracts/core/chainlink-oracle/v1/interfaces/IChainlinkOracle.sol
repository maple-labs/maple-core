// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "external-interfaces/IChainlinkAggregatorV3.sol";

import "core/globals/v1/interfaces/IMapleGlobals.sol";

/// @title ChainlinkOracle is a wrapper contract for Chainlink oracle price feeds that allows for manual price feed overrides.
interface IChainlinkOracle {

    /**
        @dev   Emits an event indicating that the price feed aggregator has changed from `oldFeed` to `newFeed`.
        @param newFeed The new price feed aggregator.
        @param oldFeed The old price feed aggregator.
     */
    event ChangeAggregatorFeed(address newFeed, address oldFeed);

    /**
        @dev   Emits an event indicating that the price has been updated manually from `oldPrice` to `newPrice`.
        @param oldPrice The old price.
        @param newPrice The new price.
     */
    event SetManualPrice(int256 oldPrice, int256 newPrice);

    /**
        @dev   Emits an event indicating whether manual price overriding is enabled.
        @param enabled The state of manual price overriding.
     */
    event SetManualOverride(bool enabled);

    /**
        @dev The Chainlink Aggregator V3 price feed.
     */
    function priceFeed() external view returns (IChainlinkAggregatorV3);

    /**
        @dev The MapleGlobals.
     */
    function globals() external view returns (IMapleGlobals);

    /**
        @dev The address of the asset token contract.
     */
    function assetAddress() external view returns (address);

    /**
        @dev Whether the price is manually overridden.
     */
    function manualOverride() external view returns (bool);

    /**
        @dev The manually overridden price.
     */
    function manualPrice() external view returns (int256);

    /**
        @return The latest price.
     */
    function getLatestPrice() external view returns (int256);

    /**
        @dev   Updates the aggregator address to `newAggregator`. 
        @dev   Only the contract Owner can call this function. 
        @dev   It emits a `ChangeAggregatorFeed` event. 
        @param newAggregator The address of a Chainlink aggregator.
     */
    function changeAggregator(address newAggregator) external;

    /**
        @return The address of the oracled currency (0x0 for ETH).
     */
    function getAssetAddress() external view returns (address);

    /**
        @return The denomination of the price.
     */
    function getDenomination() external pure returns (bytes32);

    /**
        @dev   Sets a manual price. 
        @dev   Only the contract Owner can call this function. 
        @dev   This can only be used if manualOverride == true. 
        @dev   It emits a `SetManualPrice` event. 
        @param price Price to set.
     */
    function setManualPrice(int256 price) external;

    /**
        @dev   Sets manual override, allowing for manual price setting. 
        @dev   Only the contract Owner can call this function. 
        @dev   It emits a `SetManualOverride` event. 
        @param enabled Whether manual override price should be used.
     */
    function setManualOverride(bool enabled) external;

}
