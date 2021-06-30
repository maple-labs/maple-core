// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "lib/ds-test/contracts/test.sol";

import "core/custodial-ownership-token/v1/ERC2258.sol";
import "core/globals/v1/MapleGlobals.sol";

import "../MplRewardsFactory.sol";
import "../MplRewards.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
}

contract SomeAccount {
    function tryCall(address someContract, bytes memory someData) external returns (bool ok, bytes memory returnData) {
        (ok, returnData) = someContract.call(someData);
    }

    function call(address someContract, bytes memory someData) external returns (bytes memory returnData) {
        bool ok;
        (ok, returnData) = someContract.call(someData);
        require(ok);
    }
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

    function test_setGlobals2() external {
        SomeAccount governor = new SomeAccount();
        SomeAccount notGovernor = new SomeAccount();
        MapleGlobals mapleGlobalsContract = new MapleGlobals(address(governor), address(1), address(2));
        MplRewardsFactory rewardsFactoryContract = new MplRewardsFactory(address(mapleGlobalsContract));

        {
            (bool success,) = notGovernor.tryCall(
                address(rewardsFactoryContract),
                abi.encodeWithSignature("setGlobals(address)", address(1))
            );
            assertTrue(!success);
        }

        {
            (bool success,) = governor.tryCall(
                address(rewardsFactoryContract),
                abi.encodeWithSignature("setGlobals(address)", address(1))
            );
            assertTrue(success);
            assertEq(address(rewardsFactoryContract.globals()), address(1));
        }
    }

    function test_createMplRewards() external {
        SomeAccount governor = new SomeAccount();
        SomeAccount notGovernor = new SomeAccount();
        MapleGlobals mapleGlobalsContract = new MapleGlobals(address(governor), address(1), address(2));
        MplRewardsFactory rewardsFactoryContract = new MplRewardsFactory(address(mapleGlobalsContract));
        
        {
            (bool success,) = notGovernor.tryCall(
                address(rewardsFactoryContract),
                abi.encodeWithSignature("createMplRewards(address,address)", address(1), address(2))
            );
            assertTrue(!success);
        }

        {
            (bool success, bytes memory returnData) = governor.tryCall(
                address(rewardsFactoryContract),
                abi.encodeWithSignature("createMplRewards(address,address)", address(1), address(2))
            );
            assertTrue(success);
            
            (address rewardsContract) = abi.decode(returnData, (address));
            assertTrue(rewardsFactoryContract.isMplRewards(rewardsContract));
            assertEq(address(MplRewards(rewardsContract).rewardsToken()), address(1));
            assertEq(address(MplRewards(rewardsContract).stakingToken()), address(2));
            assertEq(uint256(MplRewards(rewardsContract).rewardsDuration()), 7 days);
            assertEq(address(MplRewards(rewardsContract).owner()), address(governor));
        }
    }
}
