// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "./user/Governor.sol";

import "../MapleToken.sol";
import "../StakeLocker.sol";
import "../StakeLockerFactory.sol";

contract StakeLockerFactoryTest is TestUtil {

    Governor                        gov;
    MapleToken                      mpl;
    MapleGlobals                globals;
    StakeLockerFactory        slFactory;
    StakeLocker                      sl;

    function setUp() public {
        gov       = new Governor();
        mpl       = new MapleToken("MapleToken", "MAPL", USDC);      // Setup Maple token.
        globals   = gov.createGlobals(address(mpl), BPOOL_FACTORY);  // Setup Maple Globals.
        slFactory = new StakeLockerFactory();                        // Setup Stake Locker Factory to support Stake Locker creation.
        assertEq(slFactory.factoryType(), uint(4), "Incorrect factory type");

        sl = StakeLocker(slFactory.newLocker(address(mpl), USDC));
    }
}
