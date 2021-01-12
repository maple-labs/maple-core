// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "../FundingLockerFactory.sol";
import "../interfaces/IFundingLockerFactory.sol";

import "../interfaces/IFundingLocker.sol";

contract Person {
    function newLocker(address _addy, address _asset) external returns (address){
        return IFundingLockerFactory(_addy).newLocker(_asset);
    }
}


contract FundingLockerFactoryTest is TestUtil {
    Person	         kim;
    FundingLockerFactory fundingLockerFactory;

    function setUp() public {
        fundingLockerFactory = new FundingLockerFactory();
        kim                  = new Person();
    }

    function test_createFundingLocker() public {
	address _out = kim.newLocker(address(fundingLockerFactory),DAI);
        assertTrue(fundingLockerFactory.isLocker(_out));
        assertTrue(fundingLockerFactory.owner(_out) == address(kim));

        assertTrue(IFundingLocker(_out).loanAsset() == DAI);
        assertTrue(IFundingLocker(_out).loan() == address(kim));
    }

}
