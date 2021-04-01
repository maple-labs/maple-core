// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "./user/Governor.sol";
import "./user/Borrower.sol";

import "../CollateralLocker.sol";
import "../CollateralLockerFactory.sol";
import "module/maple-token/contracts/MapleToken.sol";

contract CollateralLockerFactoryTest is TestUtil {

    Governor                        gov;

    CollateralLockerFactory   clFactory;
    MapleToken                      mpl;
    MapleGlobals                globals;
    Borrower                        ali;

    function setUp() public {

        gov         = new Governor();                                  // Actor: Governor of Maple.

        mpl         = new MapleToken("MapleToken", "MAPL", USDC);      // Setup Maple token.
        globals     = gov.createGlobals(address(mpl));                 // Setup Maple Globals.
        clFactory   = new CollateralLockerFactory();                   // Setup Collateral Locker Factory to support Loan Factory creation.
        ali         = new Borrower();
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

        mint("USDC", address(cl),  500 * USD);
        assertTrue(!ali.try_pull(address(cl), address(ali), 10));
    }
}
