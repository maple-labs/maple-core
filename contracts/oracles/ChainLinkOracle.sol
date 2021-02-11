// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "./IChainlinkAggregatorV3.sol";
import "../interfaces/IGlobals.sol";

contract ChainLinkOracle {

    IChainlinkAggregatorV3 internal priceFeed;
    IGlobals public globals;

    bool    public manualOverride;
    address public currencyAddress;
    int     public manualPrice;

    event ChangeAggregatorFeed(address _newMedianizer, address _oldMedianizer);
    event SetManualPrice(int _oldPrice, int _newPrice);
    event SetManualOverride(bool _override);

    /**
        @dev Creates a new Chainlink based oracle
        @param _aggregator Address of Chainlink aggregator.
        @param _currencyAddress Address of currency (0x0 for ETH).
        @param _globals Address of the `MapleGlobal` contract.
      */
    constructor(address _aggregator, address _currencyAddress, address _globals) public {
        require(_aggregator != address(0), "ChainLinkOracle:INVALID_AGGREGATOR_ADDRESS");
        priceFeed       = IChainlinkAggregatorV3(_aggregator);
        currencyAddress = _currencyAddress;
        globals         = IGlobals(_globals);
    }

    /**
        @dev Returns the latest price.
     */
    function getLatestPrice() public view returns (int) {
        if (manualOverride) return manualPrice;
        (
            uint80 roundID, 
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        require(price != int(0), "ChainLinkOracle:ZERO_PRICE");
        return price;
    }


    /**
        @dev Updates aggregator address.
        @param aggregator Address of chainlink aggregator.
    */
    function changeAggregator(address aggregator) external {
        _isValidGovernor();
        require(aggregator != address(0), "ChainLinkOracle:INVALID_AGGREGATOR_ADDRESS");
        emit ChangeAggregatorFeed(aggregator, address(priceFeed));
        priceFeed = IChainlinkAggregatorV3(aggregator);
    }

    /**
        @dev Returns address of oracle currency (0x0 for ETH).
    */
    function getCurrencyAddress() external view returns(address) {
        return currencyAddress;
    }

    /**
       @dev Returns denomination of price.
    */
    function getCurrencyDenominated() external view returns(bytes32) {
        // All Chainlink oracles are denominated in USD
        return bytes32("USD");
    }

    /**
        @dev Set a manual price. NA - this will only be used if manualOverride == true
        @param _price Price to set
    */
    function setManualPrice(int _price) external {
        _isValidGovernor();
        emit SetManualPrice(manualPrice, _price);
        manualPrice = _price;
    }

    /**
        @dev Determine whether manual price is used or not
        @param _override Whether to use the manual override price or not
    */
    function setManualOverride(bool _override) external {
        _isValidGovernor();
        manualOverride = _override;
        emit SetManualOverride(_override);
    }

    function _isValidGovernor() internal view {
        require(globals.governor() == msg.sender, "ChainLink:NOT_AUTHORISED");
    }

}