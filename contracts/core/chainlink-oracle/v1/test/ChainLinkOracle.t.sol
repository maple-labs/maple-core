// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import { TestUtil } from "../../../../test/TestUtil.sol";

contract ChainlinkOracleTest is TestUtil {

    function setUp() public {
        setUpGlobals();
        createCommoner();
        setUpTokens();
        setUpOracles();
    }

    function test_getLatestPrice() public {
        // Assert initial state
        assertTrue( wethOracle.getLatestPrice() > int256(1));
        assertTrue(!wethOracle.manualOverride());
        assertEq(   wethOracle.manualPrice(), int256(0));

        // Try to set manual price before setting the manual override.
        assertTrue(!securityAdmin.try_setManualPrice(address(wethOracle), int256(45000)));

        // Enable oracle manual override
        assertTrue(         !cam.try_setManualOverride(address(wethOracle), true));
        assertTrue(securityAdmin.try_setManualOverride(address(wethOracle), true));
        assertTrue(   wethOracle.manualOverride());

        // Set price manually
        assertTrue(         !cam.try_setManualPrice(address(wethOracle), int256(45000)));
        assertTrue(securityAdmin.try_setManualPrice(address(wethOracle), int256(45000)));
        assertEq(     wethOracle.manualPrice(),    int256(45000));
        assertEq(     wethOracle.getLatestPrice(), int256(45000));

        // Change aggregator
        assertTrue(         !cam.try_changeAggregator(address(wethOracle), 0xb022E2970b3501d8d83eD07912330d178543C1eB));
        assertTrue(securityAdmin.try_changeAggregator(address(wethOracle), 0xb022E2970b3501d8d83eD07912330d178543C1eB));
        assertEq(address(wethOracle.priceFeed()),                          0xb022E2970b3501d8d83eD07912330d178543C1eB);
    }
}
