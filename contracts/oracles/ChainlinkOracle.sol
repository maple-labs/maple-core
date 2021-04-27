// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "./IChainlinkAggregatorV3.sol";
import "../interfaces/IMapleGlobals.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/// @title ChainlinkOracle is a wrapper contract for Chainlink oracle price feeds that allows for manual price feed overrides.
contract ChainlinkOracle is Ownable {

    IChainlinkAggregatorV3 public priceFeed;
    IMapleGlobals public globals;

    address public immutable assetAddress;

    bool   public manualOverride;
    int256 public manualPrice;

    event ChangeAggregatorFeed(address _newMedianizer, address _oldMedianizer);
    event       SetManualPrice(int256 _oldPrice, int256 _newPrice);
    event    SetManualOverride(bool _override);

    /**
        @dev Creates a new Chainlink based oracle.
        @param _aggregator   Address of Chainlink aggregator
        @param _assetAddress Address of currency (0x0 for ETH)
        @param _owner        Address of the owner of the contract
      */
    constructor(address _aggregator, address _assetAddress, address _owner) public {
        require(_aggregator != address(0), "CO:ZERO_AGGREGATOR_ADDR");
        priceFeed       = IChainlinkAggregatorV3(_aggregator);
        assetAddress    = _assetAddress;
        transferOwnership(_owner);
    }

    /**
        @dev Returns the latest price.
        @return price The latest price.
     */
    function getLatestPrice() public view returns (int256) {
        if (manualOverride) return manualPrice;
        (uint80 roundID, int256 price,,uint256 timeStamp, uint80 answeredInRound) = priceFeed.latestRoundData();

        require(timeStamp != 0,             "CO:ROUND_NOT_COMPLETE");
        require(answeredInRound >= roundID,         "CO:STALE_DATA");
        require(price != int256(0),                 "CO:ZERO_PRICE");
        return price;
    }


    /**
        @dev Updates aggregator address. Only the contract Owner can call this fucntion.
        @dev It emits a `ChangeAggregatorFeed` event.
        @param aggregator Address of chainlink aggregator
    */
    function changeAggregator(address aggregator) external onlyOwner {
        require(aggregator != address(0), "CO:ZERO_AGGREGATOR_ADDR");
        emit ChangeAggregatorFeed(aggregator, address(priceFeed));
        priceFeed = IChainlinkAggregatorV3(aggregator);
    }

    /**
        @dev Returns address of oracle currency (0x0 for ETH).
    */
    function getAssetAddress() external view returns(address) {
        return assetAddress;
    }

    /**
       @dev Returns denomination of price.
    */
    function getDenomination() external pure returns(bytes32) {
        // All Chainlink oracles are denominated in USD
        return bytes32("USD");
    }

    /**
        @dev Set a manual price.  Only the contract Owner can call this fucntion.
             NOTE: this can only be used if manualOverride == true.
        @dev It emits a `SetManualPrice` event.
        @param _price Price to set
    */
    function setManualPrice(int256 _price) public onlyOwner {
        require(manualOverride, "CO:MANUAL_OVERRIDE_NOT_ACTIVE");
        emit SetManualPrice(manualPrice, _price);
        manualPrice = _price;
    }

    /**
        @dev Set manual override, allowing for manual price setting. Only the contract Owner can call this fucntion.
        @dev It emits a `SetManualOverride` event.
        @param _override Whether to use the manual override price or not
    */
    function setManualOverride(bool _override) public onlyOwner {
        manualOverride = _override;
        emit SetManualOverride(_override);
    }

}
