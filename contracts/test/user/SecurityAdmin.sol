// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "../../interfaces/IOracle.sol";
import "../../interfaces/IPool.sol";
import "../../oracles/ChainlinkOracle.sol";

contract SecurityAdmin {

    function claim(address pool, address loan, address dlFactory) external { IPool(pool).claim(loan, dlFactory); }
    function setManualPrice(address target, int256 price)         external { IOracle(target).setManualPrice(price); }
    function setManualOverride(address target, bool _override)    external { IOracle(target).setManualOverride(_override); }
    function changeAggregator(address target, address aggregator) external { IOracle(target).changeAggregator(aggregator); }

    function try_claim(address pool, address loan, address dlFactory) external returns (bool ok) {
        string memory sig = "claim(address,address)";
        (ok,) = pool.call(abi.encodeWithSignature(sig, loan, dlFactory));
    }

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
}
