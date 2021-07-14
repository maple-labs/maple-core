// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { Ownable } from "../../../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

import { IChainlinkAggregatorV3 } from "../../../external-interfaces/IChainlinkAggregatorV3.sol";

import { IMapleGlobals } from "../../globals/v1/interfaces/IMapleGlobals.sol";

import { IChainlinkOracle } from "./interfaces/IChainlinkOracle.sol";

/// @title ChainlinkOracle is a wrapper contract for Chainlink oracle price feeds that allows for manual price feed overrides.
contract ChainlinkOracle is IChainlinkOracle, Ownable {

    IChainlinkAggregatorV3 public override priceFeed;
    IMapleGlobals public override globals;

    address public override immutable assetAddress;

    bool   public override manualOverride;
    int256 public override manualPrice;

    /**
        @dev   Creates a new Chainlink based oracle.
        @param _aggregator   Address of Chainlink aggregator.
        @param _assetAddress Address of currency (0x0 for ETH).
        @param _owner        Address of the owner of the contract.
     */
    constructor(address _aggregator, address _assetAddress, address _owner) public {
        require(_aggregator != address(0), "CO:ZERO_AGGREGATOR_ADDR");
        priceFeed       = IChainlinkAggregatorV3(_aggregator);
        assetAddress    = _assetAddress;
        transferOwnership(_owner);
    }

    function getLatestPrice() public override view returns (int256) {
        if (manualOverride) return manualPrice;
        (uint80 roundID, int256 price,,uint256 timeStamp, uint80 answeredInRound) = priceFeed.latestRoundData();

        require(timeStamp != 0,             "CO:ROUND_NOT_COMPLETE");
        require(answeredInRound >= roundID,         "CO:STALE_DATA");
        require(price != int256(0),                 "CO:ZERO_PRICE");
        return price;
    }

    function changeAggregator(address aggregator) external override onlyOwner {
        require(aggregator != address(0), "CO:ZERO_AGGREGATOR_ADDR");
        emit ChangeAggregatorFeed(aggregator, address(priceFeed));
        priceFeed = IChainlinkAggregatorV3(aggregator);
    }

    function getAssetAddress() external override view returns (address) {
        return assetAddress;
    }

    function getDenomination() external override pure returns (bytes32) {
        // All Chainlink oracles are denominated in USD.
        return bytes32("USD");
    }

    function setManualPrice(int256 _price) public override onlyOwner {
        require(manualOverride, "CO:MANUAL_OVERRIDE_NOT_ACTIVE");
        emit SetManualPrice(manualPrice, _price);
        manualPrice = _price;
    }

    function setManualOverride(bool _override) public override onlyOwner {
        manualOverride = _override;
        emit SetManualOverride(_override);
    }

}
