// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "../LiquidityLockerFactory.sol";
import "../interfaces/ILiquidityLockerFactory.sol";

import "../interfaces/ILiquidityLocker.sol";


contract LiquidityLockerFactoryTest is TestUtil {
    User                   kim;
    LiquidityLockerFactory liquidityLockerFactory;

    function setUp() public {
        liquidityLockerFactory = new LiquidityLockerFactory();
        kim                    = new User();
    }

    function test_createLiquidityLocker() public {
        address locker = kim.newLocker(address(liquidityLockerFactory), DAI);

        assertTrue(liquidityLockerFactory.isLocker(locker));

        assertTrue(liquidityLockerFactory.owner(locker)      == address(kim));
        assertTrue(ILiquidityLocker(locker).owner()          == address(kim));
        assertTrue(ILiquidityLocker(locker).liquidityAsset() == DAI);
    }

}
