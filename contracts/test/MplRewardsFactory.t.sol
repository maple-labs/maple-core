// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

contract MplRewardsFactoryTest is TestUtil {

    function setUp() public {
        setUpGlobals();
        setUpMplRewardsFactory();
    }

    function test_constructor() public {
        MplRewardsFactory _mplRewardsFactory = new MplRewardsFactory(address(globals));  // Setup MplRewardsFactory to support MplRewards creation.
        assertEq(address(_mplRewardsFactory.globals()), address(globals));
    }

    function test_createMplRewards() public {
        address mockPool = address(1);  // Fake pool address so a pool doesn't have to be instantiated for PoolFDTs

        // Assert permissioning
        assertTrue(!fakeGov.try_createMplRewards(address(mpl), mockPool));
        assertTrue(     gov.try_createMplRewards(address(mpl), mockPool));

        MplRewards mplRewards = MplRewards(gov.createMplRewards(address(mpl), mockPool));

        // Validate the storage of mplRewardsFactory
        assertTrue(mplRewardsFactory.isMplRewards(address(mplRewards)));

        // Validate the storage of mplRewards.
        assertEq(address(mplRewards.rewardsToken()), address(mpl));
        assertEq(address(mplRewards.stakingToken()),     mockPool);
        assertEq(mplRewards.rewardsDuration(),             7 days);
        assertEq(address(mplRewards.owner()),        address(gov));
    }

    function test_setGlobals() public {
        assertTrue(!fakeGov.try_setGlobals(address(mplRewardsFactory), address(1)));
        assertTrue(     gov.try_setGlobals(address(mplRewardsFactory), address(1)));
        assertEq(address(mplRewardsFactory.globals()), address(1));
    }
}
