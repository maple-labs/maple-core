// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

contract Commoner {

    function try_setLiquidityCap(address pool, uint256 liquidityCap) external returns(bool ok) {
        string memory sig = "setLiquidityCap(uint256)";
        (ok,) = address(pool).call(abi.encodeWithSignature(sig, liquidityCap));
    }

    function try_triggerDefault(address loan) external returns (bool ok) {
        string memory sig = "triggerDefault()";
        (ok,) = loan.call(abi.encodeWithSignature(sig));
    }

    function try_setProtocolPause(address globals, bool pause) external returns (bool ok) {
        string memory sig = "setProtocolPause(bool)";
        (ok,) = globals.call(abi.encodeWithSignature(sig, pause));
    }

    function try_setManualOverride(address oracle, bool _override) external returns (bool ok) {
        string memory sig = "setManualOverride(bool)";
        (ok,) = oracle.call(abi.encodeWithSignature(sig, _override));
    }

    function try_setManualPrice(address oracle, int256 priceFeed) external returns (bool ok) {
        string memory sig = "setManualPrice(int256)";
        (ok,) = oracle.call(abi.encodeWithSignature(sig, priceFeed));
    }

    function try_changeAggregator(address oracle, address aggregator) external returns (bool ok) {
        string memory sig = "changeAggregator(address)";
        (ok,) = oracle.call(abi.encodeWithSignature(sig, aggregator));
    }

    function try_pause(address target) external returns (bool ok) {
        string memory sig = "pause()";
        (ok,) = target.call(abi.encodeWithSignature(sig));
    }

    function try_unpause(address target) external returns (bool ok) {
        string memory sig = "unpause()";
        (ok,) = target.call(abi.encodeWithSignature(sig));
    }
}
