// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "lib/ds-test/contracts/test.sol";

import "core/globals/v1/MapleGlobals.sol";

import "../MplRewards.sol";
import "../MplRewardsFactory.sol";

import "./accounts/MplRewardsFactoryGovernor.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
}

contract MplRewardsFactoryTest is DSTest {

    Hevm hevm;

    constructor() public {
        hevm = Hevm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));
    }

    function test_constructor() external {
        MplRewardsFactory rewardsFactoryContract = new MplRewardsFactory(address(1));
        assertEq(address(rewardsFactoryContract.globals()), address(1));
    }

    function test_setGlobals() external {
        MplRewardsFactoryGovernor governor       = new MplRewardsFactoryGovernor();
        MplRewardsFactoryGovernor notGovernor    = new MplRewardsFactoryGovernor();
        MapleGlobals mapleGlobalsContract        = new MapleGlobals(address(governor), address(1), address(2));
        MplRewardsFactory rewardsFactoryContract = new MplRewardsFactory(address(mapleGlobalsContract));

        assertTrue(!notGovernor.try_mplRewards_setGlobals(address(rewardsFactoryContract), address(1)));
        assertTrue(    governor.try_mplRewards_setGlobals(address(rewardsFactoryContract), address(1)));
    }

    function test_createMplRewards() external {
        MplRewardsFactoryGovernor governor       = new MplRewardsFactoryGovernor();
        MplRewardsFactoryGovernor notGovernor    = new MplRewardsFactoryGovernor();
        MapleGlobals mapleGlobalsContract        = new MapleGlobals(address(governor), address(1), address(2));
        MplRewardsFactory rewardsFactoryContract = new MplRewardsFactory(address(mapleGlobalsContract));
        
        assertTrue(!notGovernor.try_mplRewards_createMplRewards(address(rewardsFactoryContract), address(1), address(2)));

        address rewardsContract = governor.mplRewards_createMplRewards(rewardsFactoryContract, address(1), address(2));

        assertTrue(rewardsFactoryContract.isMplRewards(rewardsContract));

        assertEq(address(MplRewards(rewardsContract).rewardsToken()),    address(1));
        assertEq(address(MplRewards(rewardsContract).stakingToken()),    address(2));
        assertEq(uint256(MplRewards(rewardsContract).rewardsDuration()), 7 days);
        assertEq(address(MplRewards(rewardsContract).owner()),           address(governor));
    }
}
