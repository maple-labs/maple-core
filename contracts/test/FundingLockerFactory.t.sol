// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";
import "../FundingLockerFactory.sol";
import "../FundingLocker.sol";
import "../MapleToken.sol";
import "../MapleGlobals.sol";

contract FundingLockerFactoryTest is TestUtil {

    MapleToken                      mpl;
    MapleGlobals                globals;
    FundingLockerFactory      flFactory;

    function setUp() public {
        // Step 1: Setup Maple token.
        mpl         = new MapleToken("MapleToken", "MAPL", USDC);
        // Step 2: Setup Maple Globals.
        globals     = new MapleGlobals(address(this), address(mpl), BPOOL_FACTORY);
        // Step 3: Setup Funding Locker Factory to support Loan Factory creation.
        flFactory   = new FundingLockerFactory();

        assertEq(flFactory.factoryType(), "FundingLockerFactory", "Incorrect factory type");
    }

    function test_newLocker() public {
        FundingLocker cl  = FundingLocker(flFactory.newLocker(USDC));
        // Validate the storage of dlfactory.
        assertEq(flFactory.owner(address(cl)), address(this));
        assertTrue(flFactory.isLocker(address(cl)));

        // Validate whether the dl has a FundingLocker interface or not.
        assertEq(cl.loan(), address(this), "Incorrect loan address");
        assertEq(cl.loanAsset(), USDC, "Incorrect address of loan asset");
    }

    
}
