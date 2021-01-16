// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";
import "../CollateralLockerFactory.sol";
import "../CollateralLocker.sol";
import "../MapleToken.sol";
import "../MapleGlobals.sol";

contract CollateralLockerFactoryTest is TestUtil {

    MapleToken                      mpl;
    MapleGlobals                globals;
    CollateralLockerFactory   clFactory;

    function setUp() public {
        // Step 1: Setup Maple token.
        mpl         = new MapleToken("MapleToken", "MAPL", USDC);
        // Step 2: Setup Maple Globals.
        globals     = new MapleGlobals(address(this), address(mpl), BPOOL_FACTORY);
        // Step 3: Setup Collateral Locker Factory to support Loan Factory creation.
        clFactory   = new CollateralLockerFactory();

        assertEq(clFactory.factoryType(), "CollateralLockerFactory", "Incorrect factory type");
    }

    function test_newLocker() public {
        CollateralLocker cl  = CollateralLocker(clFactory.newLocker(USDC));
        // Validate the storage of dlfactory.
        assertEq(clFactory.owner(address(cl)), address(this));
        assertTrue(clFactory.isLocker(address(cl)));

        // Validate whether the dl has a CollateralLocker interface or not.
        assertEq(cl.loan(), address(this), "Incorrect loan address");
        assertEq(cl.collateralAsset(), USDC, "Incorrect address of collateral asset");
    }

    
}
