// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "../CollateralLockerFactory.sol";
import "../interfaces/ICollateralLockerFactory.sol";

import "../interfaces/ICollateralLocker.sol";



contract CollateralLockerFactoryTest is TestUtil {
    User                    kim;
    CollateralLockerFactory collateralLockerFactory;

    function setUp() public {
        collateralLockerFactory = new CollateralLockerFactory();
        kim                     = new User();
    }

    function test_createCollateralLocker() public {
	address locker = kim.newLocker(address(collateralLockerFactory), DAI);

        assertTrue(collateralLockerFactory.isLocker(locker));

        assertTrue(collateralLockerFactory.owner(locker)       == address(kim));
        assertTrue(ICollateralLocker(locker).collateralAsset() == DAI);
        assertTrue(ICollateralLocker(locker).loan()            == address(kim));
    }

}
