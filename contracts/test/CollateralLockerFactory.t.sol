// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "../CollateralLockerFactory.sol";
import "../interfaces/ICollateralLockerFactory.sol";

import "../interfaces/ICollateralLocker.sol";



contract CollateralLockerFactoryTest is TestUtil {
    User                 kim;
    CollateralLockerFactory collateralLockerFactory;

    function setUp() public {
        collateralLockerFactory = new CollateralLockerFactory();
        kim                     = new User();
    }

    function test_createCollateralLocker() public {
	address _out = kim.newLocker(address(collateralLockerFactory),DAI);

        assertTrue(collateralLockerFactory.isLocker(_out));

        assertTrue(collateralLockerFactory.owner(_out)       == address(kim));
        assertTrue(ICollateralLocker(_out).collateralAsset() == DAI);
        assertTrue(ICollateralLocker(_out).loan()            == address(kim));
    }

}
