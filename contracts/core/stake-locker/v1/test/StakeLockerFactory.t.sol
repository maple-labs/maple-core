// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import { TestUtil } from "../../../../test/TestUtil.sol";

contract StakeLockerFactoryTest is TestUtil {

    function setUp() public {
        setUpGlobals();
        createStakeLockerFactory();
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
