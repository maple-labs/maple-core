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

    function setUp() public {
        gov       = new Governor();
        mpl       = new MapleToken("MapleToken", "MAPL", USDC);      // Setup Maple token.
        globals   = gov.createGlobals(address(mpl), BPOOL_FACTORY);  // Setup Maple Globals.
        slFactory = new StakeLockerFactory();                        // Setup Stake Locker Factory to support Stake Locker creation.
        assertEq(slFactory.factoryType(), uint(4), "Incorrect factory type");
    }

    function test_newLocker() public {
        StakeLocker sl = StakeLocker(slFactory.newLocker(address(mpl), USDC, address(globals)));
        // Validate the storage of slfactory.
        assertEq(slFactory.owner(address(sl)), address(this));
        assertTrue(slFactory.isLocker(address(sl)));

        // Validate the storage of sl.
        assertEq(address(sl.stakeAsset()), address(mpl),     "Incorrect stake asset address");
        assertEq(sl.liquidityAsset(),      USDC,             "Incorrect address of loan asset");
        assertEq(sl.owner(),               address(this),    "Incorrect owner address");
        assertEq(address(sl.globals()),    address(globals), "Incorrect globals address");
    }
}
