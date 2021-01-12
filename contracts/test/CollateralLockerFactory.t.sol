// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "../CollateralLockerFactory.sol";
import "../interfaces/ICollateralLockerFactory.sol";

contract randomGuy {
    function newLocker(address _addy, address _asset) external returns (address){
        return ICollateralLockerFactory(_addy).newLocker(_asset);
    }
}


contract PoolFactoryTest is TestUtil {
    randomGuy	         kim;
    CollateralLockerFactory collateralLockerFactory;

    function setUp() public {
        collateralLockerFactory = new CollateralLockerFactory();
        kim                  = new randomGuy();
    }

    function test_createCollateralLocker() public {
	address _out = kim.newLocker(address(collateralLockerFactory),DAI);
        assertTrue(collateralLockerFactory.isLocker(_out));
        assertTrue(collateralLockerFactory.owner(_out) == address(kim));
    }

}
