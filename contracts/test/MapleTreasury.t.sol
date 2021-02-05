// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "./user/Governor.sol";

import "../MapleToken.sol";
import "../MapleTreasury.sol";

contract PoolDelegate { }

contract MapleTreasuryTest is TestUtil {

    Governor                         gov;

    MapleGlobals                 globals;
    MapleToken                       mpl;
    MapleTreasury                    trs;

    function setUp() public {

        gov     = new Governor();   // Actor: Governor of Maple.

        mpl     = new MapleToken("MapleToken", "MAPLE", USDC);
        globals = gov.createGlobals(address(mpl), BPOOL_FACTORY);
        trs     = new MapleTreasury(address(mpl), USDC, UNISWAP_V2_ROUTER_02, address(globals)); 

        gov.setMapleTreasury(address(trs));
    }

    function test_setGlobals() public {
        Governor fakeGov = new Governor();

        MapleGlobals globals2 = fakeGov.createGlobals(address(mpl), BPOOL_FACTORY);  // Create upgraded MapleGlobals

        assertEq(address(trs.globals()), address(globals));

        assertTrue(!fakeGov.try_setGlobals(address(trs), address(globals2)));  // Non-governor cannot set new globals

        globals2 = gov.createGlobals(address(mpl), BPOOL_FACTORY);             // Create upgraded MapleGlobals

        assertTrue(gov.try_setGlobals(address(trs), address(globals2)));       // Governor can set new globals
        assertEq(address(trs.globals()), address(globals2));                   // Globals is updated
    }
}
