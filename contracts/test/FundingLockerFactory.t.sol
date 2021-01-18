// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";
import "../MapleToken.sol";
import "../MapleGlobals.sol";
import "../FundingLocker.sol";
import "../FundingLockerFactory.sol";

contract FundingLockerFactoryTest is TestUtil {

    MapleToken                      mpl;
    MapleGlobals                globals;
    FundingLockerFactory      flFactory;

    function setUp() public {
        mpl       = new MapleToken("MapleToken", "MAPL", USDC);                    // Setup Maple token.
        globals   = new MapleGlobals(address(this), address(mpl), BPOOL_FACTORY);  // Setup Maple Globals.
        flFactory = new FundingLockerFactory();                                    // Setup Funding Locker Factory to support Loan Factory creation.
        assertEq(flFactory.factoryType(), uint(2), "Incorrect factory type");
    }

    function test_newLocker() public {
        FundingLocker fl  = FundingLocker(flFactory.newLocker(USDC));
        // Validate the storage of flfactory.
        assertEq(flFactory.owner(address(fl)), address(this));
        assertTrue(flFactory.isLocker(address(fl)));

        // Validate the storage of fl.
        assertEq(fl.loan(), address(this), "Incorrect loan address");
        assertEq(address(fl.loanAsset()), USDC, "Incorrect address of loan asset");
    }
}
