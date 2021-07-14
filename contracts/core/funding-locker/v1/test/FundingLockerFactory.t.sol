// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import { TestUtil } from "../../../../test/TestUtil.sol";

import { IFundingLocker } from "../interfaces/IFundingLocker.sol";

contract FundingLockerFactoryTest is TestUtil {

    function setUp() public {
        setUpGlobals();
        createFundingLockerFactory();
    }

    function test_newLocker() public {
        IFundingLocker fl  = IFundingLocker(flFactory.newLocker(USDC));

        // Validate the storage of flfactory.
        assertEq(flFactory.owner(address(fl)), address(this));
        assertTrue(flFactory.isLocker(address(fl)));

        // Validate the storage of fl.
        assertEq(fl.loan(), address(this),           "Incorrect loan address");
        assertEq(address(fl.liquidityAsset()), USDC, "Incorrect address of loan asset");
    }

}
