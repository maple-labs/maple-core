// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "../LiquidityLockerFactory.sol";
import "../interfaces/ILiquidityLockerFactory.sol";

import "../interfaces/ILiquidityLocker.sol";

contract Someone {
    function newLocker(address _addy, address _asset) external returns (address){
        return ILiquidityLockerFactory(_addy).newLocker(_asset);
    }
}


contract LiquidityLockerFactoryTest is TestUtil {
    Someone                kim;
    LiquidityLockerFactory liquidityLockerFactory;

    function setUp() public {
        liquidityLockerFactory = new LiquidityLockerFactory();
        kim                    = new Someone();
    }

    function test_createLiquidityLocker() public {
	address _out = kim.newLocker(address(liquidityLockerFactory),DAI);
        assertTrue(liquidityLockerFactory.isLocker(_out));
        assertTrue(liquidityLockerFactory.owner(_out) == address(kim));

        assertTrue(ILiquidityLocker(_out).owner() == address(kim));
        assertTrue(ILiquidityLocker(_out).liquidityAsset() == DAI);
    }

}
