// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "./user/Governor.sol";

import "../StakeLocker.sol";
import "../StakeLockerFactory.sol";

import "module/maple-token/contracts/MapleToken.sol";

contract StakeLockerFactoryTest is TestUtil {

    Governor                        gov;

    MapleGlobals                globals;
    MapleToken                      mpl;
    StakeLockerFactory        slFactory;

    function setUp() public {

        gov       = new Governor();                                  // Actor: Governor of Maple.

        mpl       = new MapleToken("MapleToken", "MAPL", USDC);      // Setup Maple token.
        globals   = gov.createGlobals(address(mpl), BPOOL_FACTORY);  // Setup Maple Globals.
        slFactory = new StakeLockerFactory();                        // Setup Stake Locker Factory to support Stake Locker creation.
        assertEq(slFactory.factoryType(), uint(4), "Incorrect factory type");
    }

    function test_newLocker() public {
        StakeLocker sl = StakeLocker(slFactory.newLocker(address(mpl), USDC));
        // Validate the storage of slfactory.
        assertEq(slFactory.owner(address(sl)), address(this));
        assertTrue(slFactory.isLocker(address(sl)));

        // Validate the storage of sl.
        assertEq(address(sl.stakeAsset()), address(mpl),     "Incorrect stake asset address");
        assertEq(sl.liquidityAsset(),      USDC,             "Incorrect address of loan asset");
        assertEq(sl.pool(),                address(this),    "Incorrect pool address");
    }
}
