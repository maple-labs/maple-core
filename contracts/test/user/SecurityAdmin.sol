// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "../../interfaces/IOracle.sol";
import "../../oracles/ChainlinkOracle.sol";

contract SecurityAdmin {
    function try_setManualPrice(address oracle, int256 priceFeed) external returns (bool ok) {
        string memory sig = "setManualPrice(int256)";
        (ok,) = oracle.call(abi.encodeWithSignature(sig, priceFeed));
    }

    function try_setManualOverride(address oracle, bool _override) external returns (bool ok) {
        string memory sig = "setManualOverride(bool)";
        (ok,) = oracle.call(abi.encodeWithSignature(sig, _override));
    }

    function try_changeAggregator(address oracle, address aggregator) external returns (bool ok) {
        string memory sig = "changeAggregator(address)";
        (ok,) = oracle.call(abi.encodeWithSignature(sig, aggregator));
    }

    function setManualPrice(address target, int256 price)         external { IOracle(target).setManualPrice(price);}
    function setManualOverride(address target, bool _override)    external { IOracle(target).setManualOverride(_override);}
    function changeAggregator(address target, address aggregator) external { IOracle(target).changeAggregator(aggregator);}
}