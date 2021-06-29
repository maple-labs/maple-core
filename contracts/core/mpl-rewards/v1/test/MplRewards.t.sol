// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "test/TestUtil.sol";

contract MplRewardsTest is TestUtil {

    function setUp() public {
        setUpGlobals();
        setUpTokens();
        setUpOracles();
        setUpFactories();
        setUpActors();
        setUpBalancerPool();
        setUpLiquidityPool();
        setUpMplRewardsFactory();
        setUpMplRewards(address(pool1));
        setUpFarmers(1000 * USD, 1000 * USD, 1000 * USD);
    }

    /*******************************/
    /*** Admin Functions Testing ***/
    /*******************************/
    function test_transferOwnership() public {
        assertEq(mplRewards.owner(), address(gov));

        assertTrue(!fakeGov.try_transferOwnership(address(fakeGov)));
        assertTrue(     gov.try_transferOwnership(address(fakeGov)));

        assertEq(mplRewards.owner(), address(fakeGov));

        assertTrue(   !gov.try_transferOwnership(address(gov)));
        assertTrue(fakeGov.try_transferOwnership(address(gov)));

        assertEq(mplRewards.owner(), address(gov));
    }

    function test_notifyRewardAmount() public {
        assertEq(mplRewards.periodFinish(),              0);
        assertEq(mplRewards.rewardRate(),                0);
        assertEq(mplRewards.rewardsDuration(),      7 days);  // Pre set value
        assertEq(mplRewards.lastUpdateTime(),            0);
        assertEq(mplRewards.rewardPerTokenStored(),      0);

        mpl.transfer(address(mplRewards), 25_000 * WAD);

        assertTrue(!fakeGov.try_notifyRewardAmount(25_000 * WAD));
        assertTrue(     gov.try_notifyRewardAmount(25_000 * WAD));

        assertEq(mplRewards.rewardRate(),     uint256(25_000 * WAD) / 7 days);
        assertEq(mplRewards.lastUpdateTime(),                block.timestamp);
        assertEq(mplRewards.periodFinish(),         block.timestamp + 7 days);
    }

    function test_updatePeriodFinish() public {
        assertEq(mplRewards.periodFinish(), 0);

        assertTrue(!fakeGov.try_updatePeriodFinish(block.timestamp + 30 days));
        assertTrue(     gov.try_updatePeriodFinish(block.timestamp + 30 days));

        assertEq(mplRewards.periodFinish(), block.timestamp + 30 days);
    }

    function test_recoverERC20() public {
        mint("USDC", address(fay), 1000 * USD);

        assertEq(IERC20(USDC).balanceOf(address(fay)),            1000 * USD);
        assertEq(IERC20(USDC).balanceOf(address(gov)),                     0);
        assertEq(IERC20(USDC).balanceOf(address(mplRewards)),              0);
        assertEq(mplRewards.balanceOf(address(fay)),                       0);
        assertEq(mplRewards.totalSupply(),                                 0);

        fay.transfer(USDC, address(mplRewards), 1000 * USD);  // Ali transfers USDC directly into Staking rewards accidentally

        assertEq(IERC20(USDC).balanceOf(address(fay)),                     0);
        assertEq(IERC20(USDC).balanceOf(address(gov)),                     0);
        assertEq(IERC20(USDC).balanceOf(address(mplRewards)),     1000 * USD);
        assertEq(mplRewards.balanceOf(address(fay)),                       0);
        assertEq(mplRewards.totalSupply(),                                 0);

        assertTrue(!fakeGov.try_recoverERC20(USDC, 400 * USD));
        assertTrue(     gov.try_recoverERC20(USDC, 400 * USD));

        assertEq(IERC20(USDC).balanceOf(address(fay)),                     0);
        assertEq(IERC20(USDC).balanceOf(address(gov)),             400 * USD);
        assertEq(IERC20(USDC).balanceOf(address(mplRewards)),      600 * USD);
        assertEq(mplRewards.balanceOf(address(fay)),                       0);
        assertEq(mplRewards.totalSupply(),                                 0);

        assertTrue(!fakeGov.try_recoverERC20(USDC, 600 * USD));
        assertTrue(     gov.try_recoverERC20(USDC, 600 * USD));

        assertEq(IERC20(USDC).balanceOf(address(fay)),                     0);
        assertEq(IERC20(USDC).balanceOf(address(gov)),            1000 * USD);
        assertEq(IERC20(USDC).balanceOf(address(mplRewards)),              0);
        assertEq(mplRewards.balanceOf(address(fay)),                       0);
        assertEq(mplRewards.totalSupply(),                                 0);
    }

    function test_setRewardsDuration() public {
        assertEq(mplRewards.periodFinish(),         0);
        assertEq(mplRewards.rewardsDuration(), 7 days);

        mpl.transfer(address(mplRewards), 25_000 * WAD);

        gov.notifyRewardAmount(25_000 * WAD);

        assertEq(mplRewards.periodFinish(),    block.timestamp + 7 days);
        assertEq(mplRewards.rewardsDuration(),                   7 days);

        assertTrue(!fakeGov.try_setRewardsDuration(30 days));
        assertTrue(    !gov.try_setRewardsDuration(30 days));  // Won't work because current rewards period hasn't ended

        hevm.warp(mplRewards.periodFinish());

        assertTrue(!gov.try_setRewardsDuration(30 days));  // Won't work because current rewards period hasn't ended

        hevm.warp(mplRewards.periodFinish() + 1);

        assertTrue(gov.try_setRewardsDuration(30 days));  // Works because current rewards period has ended

        assertEq(mplRewards.rewardsDuration(), 30 days);
    }

    function test_setPaused() public {
        assertTrue(!mplRewards.paused());

        // Fay can stake
        fay.increaseCustodyAllowance(address(mplRewards), 100 * WAD);
        assertTrue(fay.try_stake(100 * WAD));

        // Set to paused
        assertTrue(!fakeGov.try_setPaused(true));
        assertTrue(     gov.try_setPaused(true));

        assertTrue(mplRewards.paused());

        // Fez can't stake
        fez.increaseCustodyAllowance(address(mplRewards), 100 * WAD);
        assertTrue(!fez.try_stake(100 * WAD));

        // Fay can't withdraw
        fay.increaseCustodyAllowance(address(mplRewards), 100 * WAD);
        assertTrue(!fay.try_withdraw(100 * WAD));

        // Set to unpaused
        assertTrue(!fakeGov.try_setPaused(false));
        assertTrue(     gov.try_setPaused(false));

        assertTrue(!mplRewards.paused());
        assertTrue(fay.try_withdraw(100 * WAD));

        // Fez can stake
        fez.increaseCustodyAllowance(address(mplRewards), 100 * WAD);
        assertTrue(fez.try_stake(100 * WAD));
    }
}
