// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "./ChainLinkOracle.sol";

contract MockPriceFeedWBTC is ChainLinkOracle {
    
    constructor(address _owner, int256 _priceFeed, address _asset) ChainLinkOracle(address(0x1), _asset, _owner) public {
        manualOverride = true;
        manualPrice = _priceFeed;
    }
}
