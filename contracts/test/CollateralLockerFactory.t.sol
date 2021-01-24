// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "./user/Governor.sol";

import "../MapleToken.sol";
import "../CollateralLocker.sol";
import "../CollateralLockerFactory.sol";

contract CollateralLockerFactoryTest is TestUtil {

    Governor                        gov;
    MapleToken                      mpl;
    MapleGlobals                globals;
    CollateralLockerFactory   clFactory;

    function setUp() public {
        gov         = new Governor();
        mpl         = new MapleToken("MapleToken", "MAPL", USDC);      // Setup Maple token.
        globals     = gov.createGlobals(address(mpl), BPOOL_FACTORY);  // Setup Maple Globals.
        clFactory   = new CollateralLockerFactory();                   // Setup Collateral Locker Factory to support Loan Factory creation.
        assertEq(clFactory.factoryType(), uint(0), "Incorrect factory type");
    }

    function test_newLocker() public {
        CollateralLocker cl  = CollateralLocker(clFactory.newLocker(USDC));
        // Validate the storage of clfactory.
        assertEq(clFactory.owner(address(cl)), address(this), "Invalid owner");
        assertTrue(clFactory.isLocker(address(cl)));

        // Validate the storage of cl.
        assertEq(cl.loan(), address(this), "Incorrect loan address");
        assertEq(address(cl.collateralAsset()), USDC, "Incorrect address of collateral asset");
    }
}
