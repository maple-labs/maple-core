// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "./ChainLinkOracle.sol";

contract MockPriceFeedWBTC is ChainLinkOracle {
    
    constructor(address _aggregator, address _owner, int256 _priceFeed, address _asset) ChainLinkOracle(_aggregator, _asset, _owner) public {
        if (_aggregator == address(1)) {
            manualOverride = true;
            manualPrice = _priceFeed;
        }
    }
}
