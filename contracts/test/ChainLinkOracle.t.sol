// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "./user/Governor.sol";
import "./user/SecurityAdmin.sol";

import "../MapleGlobals.sol";
import "../MapleToken.sol";
import "../oracles/ChainlinkOracle.sol";


contract ChainlinkOracleTest is TestUtil {

    Governor                        gov;
    MapleToken                      mpl;
    MapleGlobals                globals;
    ChainlinkOracle              oracle;
    SecurityAdmin                 admin;
    SecurityAdmin             fakeAdmin;

    uint256 constant MULTIPLIER = 10 ** 6;

    function setUp() public {

        gov       = new Governor();                                           // Actor: Governor of Maple.
        mpl       = new MapleToken("MapleToken", "MAPL", USDC);               // Setup Maple token.
        globals   = gov.createGlobals(address(mpl), BPOOL_FACTORY);           // Setup Maple Globals.
        admin     = new SecurityAdmin();
        oracle    = new ChainlinkOracle(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419, address(0), address(admin));
        fakeAdmin = new SecurityAdmin();

        assertEq(address(oracle.priceFeed()), 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    }

    function test_getLatestPrice() public {
        int256 currentPrice = oracle.getLatestPrice();
        assertTrue(currentPrice > int256(1));
        assertTrue(!oracle.manualOverride());
        assertEq(oracle.manualPrice(), int256(0));
        
        // Set manual price
        assertTrue(!fakeAdmin.try_setManualOverride(address(oracle), true));
        assertTrue(     admin.try_setManualOverride(address(oracle), true));
        
        assertTrue(!fakeAdmin.try_setManualPrice(address(oracle), int256(45000)));
        assertTrue(     admin.try_setManualPrice(address(oracle), int256(45000)));

        assertTrue(oracle.manualOverride());
        assertEq(oracle.manualPrice(),    int256(45000));
        assertEq(oracle.getLatestPrice(), int256(45000));

        // Change aggregator.
        assertTrue(!fakeAdmin.try_changeAggregator(address(oracle), 0xb022E2970b3501d8d83eD07912330d178543C1eB));
        assertTrue(     admin.try_changeAggregator(address(oracle), 0xb022E2970b3501d8d83eD07912330d178543C1eB));
        assertEq(address(oracle.priceFeed()), 0xb022E2970b3501d8d83eD07912330d178543C1eB);

        assertTrue(oracle.getLatestPrice() != currentPrice);
    }
}
