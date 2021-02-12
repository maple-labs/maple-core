// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "./user/Governor.sol";

import "../MapleGlobals.sol";
import "../MapleToken.sol";
import "../oracles/ChainLinkOracle.sol";

contract FakeUser {
    function try_set_manual_price(address oracle, int256 priceFeed) external returns (bool ok) {
        string memory sig = "setManualPrice(int256)";
        (ok,) = oracle.call(abi.encodeWithSignature(sig, priceFeed));
    }

    function try_set_manual_override(address oracle, bool _override) external returns (bool ok) {
        string memory sig = "setManualOverride(bool)";
        (ok,) = oracle.call(abi.encodeWithSignature(sig, _override));
    }

    function try_change_aggregator(address oracle, address aggregator) external returns (bool ok) {
        string memory sig = "changeAggregator(address)";
        (ok,) = oracle.call(abi.encodeWithSignature(sig, aggregator));
    }
}


contract ChainLinkOracleTest is TestUtil {

    Governor                        gov;

   
    MapleToken                      mpl;
    MapleGlobals                globals;
    ChainLinkOracle              oracle;
    FakeUser                         fu;

    uint256 constant MULTIPLIER = 10 ** 6;

    function setUp() public {

        gov       = new Governor();                                           // Actor: Governor of Maple.
        mpl       = new MapleToken("MapleToken", "MAPL", USDC);               // Setup Maple token.
        globals   = gov.createGlobals(address(mpl), BPOOL_FACTORY);           // Setup Maple Globals.
        oracle    = new ChainLinkOracle(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419, address(0), address(this));
        fu        = new FakeUser();

        assertEq(address(oracle.priceFeed()), 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    }

    function test_getLatestPrice() public {
        int256 currentPrice = oracle.getLatestPrice();
        assertTrue(currentPrice > int256(1));
        assertTrue(!oracle.manualOverride());
        assertEq(oracle.manualPrice(), int256(0));
        
        // Set manual price
        assertTrue(!fu.try_set_manual_override(address(oracle), true));
        assertTrue(!fu.try_set_manual_price(address(oracle), int256(45000)));
        // Use authorized owner.
        oracle.setManualOverride(true);
        oracle.setManualPrice(int256(45000));
        assertTrue(oracle.manualOverride());

        assertEq(oracle.manualPrice(),    int256(45000));
        assertEq(oracle.getLatestPrice(), int256(45000));

        // Change aggregator.
        assertTrue(!fu.try_change_aggregator(address(oracle), 0xb022E2970b3501d8d83eD07912330d178543C1eB));
        oracle.changeAggregator(0xb022E2970b3501d8d83eD07912330d178543C1eB);
        assertEq(address(oracle.priceFeed()), 0xb022E2970b3501d8d83eD07912330d178543C1eB);

        assertTrue(oracle.getLatestPrice() != currentPrice);
    }
}
