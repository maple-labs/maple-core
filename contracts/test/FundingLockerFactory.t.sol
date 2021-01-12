// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "../FundingLockerFactory.sol";
import "../interfaces/IFundingLockerFactory.sol";

import "../interfaces/IFundingLocker.sol";


contract FundingLockerFactoryTest is TestUtil {
    User	             kim;
    FundingLockerFactory fundingLockerFactory;

    function setUp() public {
        fundingLockerFactory = new FundingLockerFactory();
        kim                  = new User();
    }

    function test_createFundingLocker() public {
	address locker = kim.newLocker(address(fundingLockerFactory), DAI);

        assertTrue(fundingLockerFactory.isLocker(locker));

        assertTrue(fundingLockerFactory.owner(locker) == address(kim));
        assertTrue(IFundingLocker(locker).loanAsset() == DAI);
        assertTrue(IFundingLocker(locker).loan()      == address(kim));
    }

}
