// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "./user/Governor.sol";

import "module/maple-token/contracts/MapleToken.sol";
import "../FundingLocker.sol";
import "../FundingLockerFactory.sol";

contract FundingLockerFactoryTest is TestUtil {

    Governor                        gov;
    
    FundingLockerFactory      flFactory;
    MapleToken                      mpl;
    MapleGlobals                globals;

    function setUp() public {

        gov       = new Governor();                                  // Actor: Governor of Maple.

        mpl       = new MapleToken("MapleToken", "MAPL", USDC);      // Setup Maple token.
        globals   = gov.createGlobals(address(mpl));                 // Setup Maple Globals.
        flFactory = new FundingLockerFactory();                      // Setup Funding Locker Factory to support Loan Factory creation.
        assertEq(flFactory.factoryType(), uint(2), "Incorrect factory type");
    }

    function test_newLocker() public {
        FundingLocker fl  = FundingLocker(flFactory.newLocker(USDC));
        // Validate the storage of flfactory.
        assertEq(flFactory.owner(address(fl)), address(this));
        assertTrue(flFactory.isLocker(address(fl)));

        // Validate the storage of fl.
        assertEq(fl.loan(), address(this), "Incorrect loan address");
        assertEq(address(fl.liquidityAsset()), USDC, "Incorrect address of loan asset");
    }
}
