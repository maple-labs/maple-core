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
        setUpMplRewards();
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

        fay.transfer(USDC, address(mplRewards), 1000 * USD); // Ali transfers USDC directly into Staking rewards accidentally

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
        assertTrue(    !gov.try_setRewardsDuration(30 days)); // Won't work because current rewards period hasn't ended

        hevm.warp(mplRewards.periodFinish());

        assertTrue(!gov.try_setRewardsDuration(30 days)); // Won't work because current rewards period hasn't ended

        hevm.warp(mplRewards.periodFinish() + 1);

        assertTrue(gov.try_setRewardsDuration(30 days)); // Works because current rewards period has ended

        assertEq(mplRewards.rewardsDuration(), 30 days);
    }

    function test_setPaused() public {
        assertTrue(!mplRewards.paused());

        // Fay can stake
        fay.increaseCustodyAllowance(address(pool), address(mplRewards), 100 * WAD);
        assertTrue(fay.try_stake(100 * WAD));

        // Set to paused
        assertTrue(!fakeGov.try_setPaused(true));
        assertTrue(     gov.try_setPaused(true));

        assertTrue(mplRewards.paused());

        // Fez can't stake
        fez.increaseCustodyAllowance(address(pool), address(mplRewards), 100 * WAD);
        assertTrue(!fez.try_stake(100 * WAD));

        // Fay can't withdraw
        fay.increaseCustodyAllowance(address(pool), address(mplRewards), 100 * WAD);
        assertTrue(!fay.try_withdraw(100 * WAD));

        // Set to unpaused
        assertTrue(!fakeGov.try_setPaused(false));
        assertTrue(     gov.try_setPaused(false));

        assertTrue(!mplRewards.paused());
        assertTrue(fay.try_withdraw(100 * WAD));

        // Fez can stake
        fez.increaseCustodyAllowance(address(pool), address(mplRewards), 100 * WAD);
        assertTrue(fez.try_stake(100 * WAD));
    }

    /****************************/
    /*** LP functions testing ***/
    /****************************/
    function test_stake() public {
        uint256 start = block.timestamp;

        assertEq(pool.balanceOf(address(fay)),           1000 * WAD);
        assertEq(pool.depositDate(address(fay)),              start);
        assertEq(pool.depositDate(address(mplRewards)),           0);  // MplRewards depDate should always be zero so that it can avoid lockup logic
        assertEq(mplRewards.balanceOf(address(fay)),              0);
        assertEq(mplRewards.totalSupply(),                        0);

        hevm.warp(start + 1 days); // Warp to ensure no effect on depositDates

        assertTrue(!fay.try_stake(100 * WAD));  // Can't stake before approval

        fay.increaseCustodyAllowance(address(pool), address(mplRewards), 100 * WAD);

        assertTrue(!fay.try_stake(0));          // Can't stake zero
        assertTrue( fay.try_stake(100 * WAD));  // Can stake after approval

        assertEq(pool.balanceOf(address(fay)),          1000 * WAD);  // PoolFDT balance doesn't change
        assertEq(pool.depositDate(address(fay)),             start);  // Has not changed
        assertEq(pool.depositDate(address(mplRewards)),          0);  // Has not changed
        assertEq(mplRewards.balanceOf(address(fay)),     100 * WAD);
        assertEq(mplRewards.totalSupply(),               100 * WAD);
    }

    function test_withdraw() public {
        uint256 start = block.timestamp;

        fay.increaseCustodyAllowance(address(pool), address(mplRewards), 100 * WAD);
        fay.stake(100 * WAD);

        hevm.warp(start + 1 days); // Warp to ensure no effect on depositDates

        assertEq(pool.balanceOf(address(fay)),           1000 * WAD);  // PoolFDT balance doesn't change
        assertEq(pool.depositDate(address(fay)),              start);
        assertEq(pool.depositDate(address(mplRewards)),           0);  // MplRewards depDate should always be zero so that it can avoid lockup logic
        assertEq(mplRewards.balanceOf(address(fay)),      100 * WAD);
        assertEq(mplRewards.totalSupply(),                100 * WAD);

        assertTrue(!fay.try_withdraw(0));          // Can't withdraw zero
        assertTrue( fay.try_withdraw(100 * WAD));  // Can withdraw

        assertEq(pool.balanceOf(address(fay)),           1000 * WAD);
        assertEq(pool.depositDate(address(fay)),              start);  // Does not change
        assertEq(pool.depositDate(address(mplRewards)),           0);  // MplRewards depDate should always be zero so that it can avoid lockup logic
        assertEq(mplRewards.balanceOf(address(fay)),              0);
        assertEq(mplRewards.totalSupply(),                        0);
    }

    function assertRewardsAccounting(
        address account,
        uint256 totalSupply,
        uint256 rewardPerTokenStored,
        uint256 userRewardPerTokenPaid,
        uint256 earned,
        uint256 rewards,
        uint256 rewardTokenBal
    )
        public
    {
        assertEq(mplRewards.totalSupply(),                   totalSupply);
        assertEq(mplRewards.rewardPerTokenStored(),          rewardPerTokenStored);
        assertEq(mplRewards.userRewardPerTokenPaid(account), userRewardPerTokenPaid);
        assertEq(mplRewards.earned(account),                 earned);
        assertEq(mplRewards.rewards(account),                rewards);
        assertEq(mpl.balanceOf(account),                     rewardTokenBal);
    }

    /**********************************/
    /*** Rewards accounting testing ***/
    /**********************************/
    function test_rewards_single_epoch() public {
        fay.increaseCustodyAllowance(address(pool), address(mplRewards), 100 * WAD);
        fez.increaseCustodyAllowance(address(pool), address(mplRewards), 100 * WAD);
        fay.stake(10 * WAD);

        mpl.transfer(address(mplRewards), 25_000 * WAD);

        gov.setRewardsDuration(30 days);

        gov.notifyRewardAmount(25_000 * WAD);

        uint256 rewardRate = mplRewards.rewardRate();
        uint256 start      = block.timestamp;

        assertEq(rewardRate, uint256(25_000 * WAD) / 30 days);

        assertEq(mpl.balanceOf(address(mplRewards)), 25_000 * WAD);

        /*** Ali time = 0 post-stake ***/
        assertRewardsAccounting({
            account:                address(fay),  // Account for accounting
            totalSupply:            10 * WAD,      // Ali's stake
            rewardPerTokenStored:   0,             // Starting state
            userRewardPerTokenPaid: 0,             // Starting state
            earned:                 0,             // Starting state
            rewards:                0,             // Starting state
            rewardTokenBal:         0              // Starting state
        });

        fay.getReward();  // Get reward at time = 0

        /*** Ali time = (0 days) post-claim ***/
        assertRewardsAccounting({
            account:                address(fay),  // Account for accounting
            totalSupply:            10 * WAD,      // Ali's stake
            rewardPerTokenStored:   0,             // Starting state (getReward has no effect at time = 0)
            userRewardPerTokenPaid: 0,             // Starting state (getReward has no effect at time = 0)
            earned:                 0,             // Starting state (getReward has no effect at time = 0)
            rewards:                0,             // Starting state (getReward has no effect at time = 0)
            rewardTokenBal:         0              // Starting state (getReward has no effect at time = 0)
        });

        hevm.warp(start + 1 days);  // Warp to time = (1 days) (dTime = 1 days)

        // Reward per token (RPT) that was used before fez entered the pool (accrued over dTime = 1 days)
        uint256 dTime1_rpt = rewardRate * 1 days * WAD / (10 * WAD);

        /*** Ali time = (1 days) pre-claim ***/
        assertRewardsAccounting({
            account:                address(fay),                 // Account for accounting
            totalSupply:            10 * WAD,                     // Ali's stake
            rewardPerTokenStored:   0,                            // Not updated yet
            userRewardPerTokenPaid: 0,                            // Not updated yet
            earned:                 dTime1_rpt * 10 * WAD / WAD,  // Time-based calculation
            rewards:                0,                            // Not updated yet
            rewardTokenBal:         0                             // Nothing claimed
        });

        fay.getReward();  // Get reward at time = (1 days)

        /*** Ali time = (1 days) post-claim ***/
        assertRewardsAccounting({
            account:                address(fay),                // Account for accounting
            totalSupply:            10 * WAD,                    // Ali's stake
            rewardPerTokenStored:   dTime1_rpt,                  // Updated on updateReward
            userRewardPerTokenPaid: dTime1_rpt,                  // Updated on updateReward for 100% ownership in pool after 1hr
            earned:                 0,                           // Time-based calculation and userRewardPerTokenPaid cancel out
            rewards:                0,                           // Updated on updateReward to earned(), then set to zero on getReward
            rewardTokenBal:         dTime1_rpt * 10 * WAD / WAD  // Updated on getReward, account has claimed rewards (equal to original earned() amt at this timestamp))
        });

        fez.stake(10 * WAD); // Bob stakes 10 FDTs, giving him 50% stake in the pool rewards going forward

        /*** Bob time = (1 days) post-stake ***/
        assertRewardsAccounting({
            account:                address(fez),  // Account for accounting
            totalSupply:            20 * WAD,      // Ali + Bob stake
            rewardPerTokenStored:   dTime1_rpt,    // Doesn't change since no time has passed
            userRewardPerTokenPaid: dTime1_rpt,    // Used so Bob can't claim past rewards
            earned:                 0,             // Time-based calculation and userRewardPerTokenPaid cancel out, meaning Bob only earns future rewards
            rewards:                0,             // Not updated yet
            rewardTokenBal:         0              // Not updated yet
        });

        hevm.warp(start + 2 days);  // Warp to time = (2 days) (dTime = 1 days)

        // Reward per token (RPT) that was used after Bob entered the pool (accrued over dTime = 1 days, on second day), smaller since supply increased
        uint256 dTime2_rpt = rewardRate * 1 days * WAD / (20 * WAD);

        /*** Ali time = (2 days) pre-claim ***/
        assertRewardsAccounting({
            account:                address(fay),                 // Account for accounting
            totalSupply:            20 * WAD,                     // Ali + Bob stake
            rewardPerTokenStored:   dTime1_rpt,                   // Not updated yet
            userRewardPerTokenPaid: dTime1_rpt,                   // Used so Ali can't do multiple claims
            earned:                 dTime2_rpt * 10 * WAD / WAD,  // Ali has not claimed any rewards that have accrued during dTime2
            rewards:                0,                            // Not updated yet
            rewardTokenBal:         dTime1_rpt * 10 * WAD / WAD   // From previous claim
        });

        /*** Bob time = (2 days) pre-claim ***/
        assertRewardsAccounting({
            account:                address(fez),                 // Account for accounting
            totalSupply:            20 * WAD,                     // Ali + Bob stake
            rewardPerTokenStored:   dTime1_rpt,                   // Not updated yet
            userRewardPerTokenPaid: dTime1_rpt,                   // Used so Bob can't do claims on past rewards
            earned:                 dTime2_rpt * 10 * WAD / WAD,  // Bob has not claimed any rewards that have accrued during dTime2
            rewards:                0,                            // Not updated yet
            rewardTokenBal:         0                             // Not updated yet
        });

        fez.stake(20 * WAD); // Bob stakes another 20 FDTs, giving him 75% stake in the pool rewards going forward

        /*** Bob time = (2 days) post-stake ***/
        assertRewardsAccounting({
            account:                address(fez),                 // Account for accounting
            totalSupply:            40 * WAD,                     // Ali + Bob stake
            rewardPerTokenStored:   dTime1_rpt + dTime2_rpt,      // Updated on updateReward to snapshot rewardPerToken up to that point
            userRewardPerTokenPaid: dTime1_rpt + dTime2_rpt,      // Used so Bob can't do claims on past rewards
            earned:                 dTime2_rpt * 10 * WAD / WAD,  // Earned updated to reflect all unclaimed earnings pre stake
            rewards:                dTime2_rpt * 10 * WAD / WAD,  // Rewards updated to earnings on updateReward
            rewardTokenBal:         0                             // Not updated yet
        });

        hevm.warp(start + 2 days + 1 hours);  // Warp to time = (2 days + 1 hours) (dTime = 1 hours)

        uint256 dTime3_rpt = rewardRate * 1 hours * WAD / (40 * WAD);  // Reward per token (RPT) that was used after Bob staked more into the pool (accrued over dTime = 1 hours)

        /*** Ali time = (2 days + 1 hours) pre-claim ***/
        assertRewardsAccounting({
            account:                address(fay),                                // Account for accounting
            totalSupply:            40 * WAD,                                    // Ali + Bob stake
            rewardPerTokenStored:   dTime1_rpt + dTime2_rpt,                     // Not updated yet
            userRewardPerTokenPaid: dTime1_rpt,                                  // Used so Ali can't do multiple claims
            earned:                 (dTime2_rpt + dTime3_rpt) * 10 * WAD / WAD,  // Ali has not claimed any rewards that have accrued during dTime2 or dTime3
            rewards:                0,                                           // Not updated yet
            rewardTokenBal:         dTime1_rpt * 10 * WAD / WAD                  // From previous claim
        });

        /*** Bob time = (2 days + 1 hours) pre-claim ***/
        assertRewardsAccounting({
            account:                address(fez),                                           // Account for accounting
            totalSupply:            40 * WAD,                                               // Ali + Bob stake
            rewardPerTokenStored:   dTime1_rpt + dTime2_rpt,                                // Not updated yet
            userRewardPerTokenPaid: dTime1_rpt + dTime2_rpt,                                // Used so Bob can't do claims on past rewards
            earned:                 (dTime2_rpt * 10 * WAD + dTime3_rpt * 30 * WAD) / WAD,  // Bob's earnings since he entered the pool
            rewards:                dTime2_rpt * 10 * WAD / WAD,                            // Rewards updated to reflect all unclaimed earnings pre stake
            rewardTokenBal:         0                                                       // Not updated yet
        });

        fez.getReward();  // Get reward at time = (2 days + 1 hours)

        /*** Bob time = (2 days + 1 hours) post-claim ***/
        assertRewardsAccounting({
            account:                address(fez),                                          // Account for accounting
            totalSupply:            40 * WAD,                                              // Ali + Bob stake
            rewardPerTokenStored:   dTime1_rpt + dTime2_rpt + dTime3_rpt,                  // Updated on updateReward
            userRewardPerTokenPaid: dTime1_rpt + dTime2_rpt + dTime3_rpt,                  // Used so Bob can't do multiple claims
            earned:                 0,                                                     // Time-based calculation and userRewardPerTokenPaid cancel out
            rewards:                0,                                                     // Updated on updateReward to earned(), then set to zero on getReward
            rewardTokenBal:         (dTime2_rpt * 10 * WAD + dTime3_rpt * 30 * WAD) / WAD  // Updated on getReward, account has claimed rewards (equal to original earned() amt at this timestamp))
        });

        fez.getReward();  // Try double claim

        /*** Bob time = (2 days + 1 hours) post-claim (ASSERT NOTHING CHANGES) ***/
        assertRewardsAccounting({
            account:                address(fez),                                          // Doesn't change
            totalSupply:            40 * WAD,                                              // Doesn't change
            rewardPerTokenStored:   dTime1_rpt + dTime2_rpt + dTime3_rpt,                  // Doesn't change
            userRewardPerTokenPaid: dTime1_rpt + dTime2_rpt + dTime3_rpt,                  // Doesn't change
            earned:                 0,                                                     // Doesn't change
            rewards:                0,                                                     // Doesn't change
            rewardTokenBal:         (dTime2_rpt * 10 * WAD + dTime3_rpt * 30 * WAD) / WAD  // Doesn't change
        });

        fay.withdraw(5 * WAD);  // Ali withdraws 5 * WAD at time = (2 days + 1 hours)

        /*** Ali time = (2 days + 1 hours) pre-claim ***/
        assertRewardsAccounting({
            account:                address(fay),                                // Account for accounting
            totalSupply:            35 * WAD,                                    // Ali + Bob stake, lower now that Ali withdrew
            rewardPerTokenStored:   dTime1_rpt + dTime2_rpt + dTime3_rpt,        // From Bob's update
            userRewardPerTokenPaid: dTime1_rpt + dTime2_rpt + dTime3_rpt,        // Used so Ali can't claim past earnings
            earned:                 (dTime2_rpt + dTime3_rpt) * 10 * WAD / WAD,  // Ali has not claimed any rewards that have accrued during dTime2 and dTime3
            rewards:                (dTime2_rpt + dTime3_rpt) * 10 * WAD / WAD,  // Updated on updateReward to earned()
            rewardTokenBal:         dTime1_rpt * 10 * WAD / WAD                  // From previous claim
        });

        hevm.warp(start + 3 days + 1 hours);  // Warp to time = (3 days + 1 hours) (dTime = 1 days)

        uint256 dTime4_rpt = rewardRate * 1 days * WAD / (35 * WAD);  // Reward per token (RPT) that was used after Ali withdrew from the pool (accrued over dTime = 1 days)

        /*** Ali time = (3 days + 1 hours) pre-exit ***/
        assertRewardsAccounting({
            account:                address(fay),                                                         // Account for accounting
            totalSupply:            35 * WAD,                                                             // Ali + Bob stake
            rewardPerTokenStored:   dTime1_rpt + dTime2_rpt + dTime3_rpt,                                 // Not updated yet
            userRewardPerTokenPaid: dTime1_rpt + dTime2_rpt + dTime3_rpt,                                 // Used so Ali can't do multiple claims
            earned:                 ((dTime2_rpt + dTime3_rpt) * 10 * WAD + dTime4_rpt * 5 * WAD) / WAD,  // Ali has not claimed any rewards that have accrued during dTime2, dTime3 and dTime4
            rewards:                (dTime2_rpt + dTime3_rpt) * 10 * WAD / WAD,                           // Not updated yet
            rewardTokenBal:         dTime1_rpt * 10 * WAD / WAD                                           // From previous claim
        });

        /*** Bob time = (2 days + 1 hours) pre-exit ***/
        assertRewardsAccounting({
            account:                address(fez),                                          // Account for accounting
            totalSupply:            35 * WAD,                                              // Ali + Bob stake
            rewardPerTokenStored:   dTime1_rpt + dTime2_rpt + dTime3_rpt,                  // Not updated yet
            userRewardPerTokenPaid: dTime1_rpt + dTime2_rpt + dTime3_rpt,                  // Used so Bob can't do multiple claims
            earned:                 dTime4_rpt * 30 * WAD / WAD,                           // Bob has not claimed any rewards that have accrued during dTime4
            rewards:                0,                                                     // Not updated yet
            rewardTokenBal:         (dTime2_rpt * 10 * WAD + dTime3_rpt * 30 * WAD) / WAD  // From previous claim
        });

        fay.exit();  // Ali exits at time = (3 days + 1 hours)
        fez.exit();  // Bob exits at time = (3 days + 1 hours)

        /*** Ali time = (3 days + 1 hours) post-exit ***/
        assertRewardsAccounting({
            account:                address(fay),                                                                     // Account for accounting
            totalSupply:            0,                                                                                // Ali + Bob withdrew all stake
            rewardPerTokenStored:   dTime1_rpt + dTime2_rpt + dTime3_rpt + dTime4_rpt,                                // Updated on updateReward
            userRewardPerTokenPaid: dTime1_rpt + dTime2_rpt + dTime3_rpt + dTime4_rpt,                                // Used so Ali can't do multiple claims
            earned:                 0,                                                                                // Time-based calculation and userRewardPerTokenPaid cancel out
            rewards:                0,                                                                                // Updated on updateReward to earned(), then set to zero on getReward
            rewardTokenBal:         ((dTime1_rpt + dTime2_rpt + dTime3_rpt) * 10 ether + dTime4_rpt * 5 ether) / WAD  // Total earnings from pool (using ether to avoid stack too deep)
        });

        /*** Bob time = (2 days + 1 hours) post-exit ***/
        assertRewardsAccounting({
            account:                address(fez),                                                         // Account for accounting
            totalSupply:            0,                                                                    // Ali + Bob withdrew all stake
            rewardPerTokenStored:   dTime1_rpt + dTime2_rpt + dTime3_rpt + dTime4_rpt,                    // Updated on updateReward
            userRewardPerTokenPaid: dTime1_rpt + dTime2_rpt + dTime3_rpt + dTime4_rpt,                    // Used so Bob can't do multiple claims
            earned:                 0,                                                                    // Time-based calculation and userRewardPerTokenPaid cancel out
            rewards:                0,                                                                    // Updated on updateReward to earned(), then set to zero on getReward
            rewardTokenBal:         (dTime2_rpt * 10 ether + (dTime3_rpt + dTime4_rpt) * 30 ether) / WAD  // Total earnings from pool (using ether to avoid stack too deep)
        });
    }

    function test_rewards_multi_epoch() public {
        fay.increaseCustodyAllowance(address(pool), address(mplRewards), 100 * WAD);
        fez.increaseCustodyAllowance(address(pool), address(mplRewards), 100 * WAD);

        fay.stake(10 * WAD);
        fez.stake(30 * WAD);

        /**********************/
        /*** EPOCH 1 STARTS ***/
        /**********************/

        gov.setRewardsDuration(30 days);

        mpl.transfer(address(mplRewards), 25_000 * WAD);

        gov.notifyRewardAmount(25_000 * WAD);

        uint256 rewardRate   = mplRewards.rewardRate();
        uint256 periodFinish = mplRewards.periodFinish();
        uint256 start        = block.timestamp;

        assertEq(rewardRate, uint256(25_000 * WAD) / 30 days);

        assertEq(periodFinish, start + 30 days);

        hevm.warp(periodFinish);  // Warp to the end of the epoch

        /********************/
        /*** EPOCH 1 ENDS ***/
        /********************/

        uint256 dTime1_rpt = rewardRate * 30 days * WAD / (40 * WAD);  // Reward per token (RPT) for all of epoch 1

        /*** Ali time = (30 days) pre-claim ***/
        assertRewardsAccounting({
            account:                address(fay),                 // Account for accounting
            totalSupply:            40 * WAD,                     // Ali + Bob stake
            rewardPerTokenStored:   0,                            // Not updated yet
            userRewardPerTokenPaid: 0,                            // Not updated yet
            earned:                 dTime1_rpt * 10 * WAD / WAD,  // Time-based calculation
            rewards:                0,                            // Not updated yet
            rewardTokenBal:         0                             // Total claimed earnings from pool
        });

        /*** Bob time = (30 days) pre-claim ***/
        assertRewardsAccounting({
            account:                address(fez),                 // Account for accounting
            totalSupply:            40 * WAD,                     // Ali + Bob stake
            rewardPerTokenStored:   0,                            // Not updated yet
            userRewardPerTokenPaid: 0,                            // Not updated yet
            earned:                 dTime1_rpt * 30 * WAD / WAD,  // Time-based calculation
            rewards:                0,                            // Not updated yet
            rewardTokenBal:         0                             // Total claimed earnings from pool
        });

        fay.getReward();  // Ali claims all rewards for epoch 1

        /*** Ali time = (30 days) post-claim ***/
        assertRewardsAccounting({
            account:                address(fay),                 // Account for accounting
            totalSupply:            40 * WAD,                     // Ali + Bob stake
            rewardPerTokenStored:   dTime1_rpt,                   // Updated on updateReward
            userRewardPerTokenPaid: dTime1_rpt,                   // Used so Ali can't do multiple claims
            earned:                 0,                            // Time-based calculation and userRewardPerTokenPaid cancel out
            rewards:                0,                            // Updated on updateReward to earned(), then set to zero on getReward
            rewardTokenBal:         dTime1_rpt * 10 * WAD / WAD   // Total claimed earnings from pool
        });

        assertEq(mplRewards.lastUpdateTime(),           start + 30 days);
        assertEq(mplRewards.lastTimeRewardApplicable(), start + 30 days);

        hevm.warp(periodFinish + 1 days);  // Warp another day after the epoch is finished

        assertEq(mplRewards.lastUpdateTime(),           start + 30 days);  // Doesn't change
        assertEq(mplRewards.lastTimeRewardApplicable(), start + 30 days);  // Doesn't change

        /*** Ali time = (31 days) pre-claim (ASSERT NOTHING CHANGES DUE TO EPOCH BEING OVER) ***/
        assertRewardsAccounting({
            account:                address(fay),                 // Doesn't change
            totalSupply:            40 * WAD,                     // Doesn't change
            rewardPerTokenStored:   dTime1_rpt,                   // Doesn't change
            userRewardPerTokenPaid: dTime1_rpt,                   // Doesn't change
            earned:                 0,                            // Doesn't change
            rewards:                0,                            // Doesn't change
            rewardTokenBal:         dTime1_rpt * 10 * WAD / WAD   // Doesn't change
        });

        fay.getReward();  // Ali claims rewards, but epoch 1 is finished

        /*** Ali time = (31 days) post-claim (ASSERT NOTHING CHANGES DUE TO EPOCH BEING OVER) ***/
        assertRewardsAccounting({
            account:                address(fay),                 // Doesn't change
            totalSupply:            40 * WAD,                     // Doesn't change
            rewardPerTokenStored:   dTime1_rpt,                   // Doesn't change
            userRewardPerTokenPaid: dTime1_rpt,                   // Doesn't change
            earned:                 0,                            // Doesn't change
            rewards:                0,                            // Doesn't change
            rewardTokenBal:         dTime1_rpt * 10 * WAD / WAD   // Doesn't change
        });

        /**********************/
        /*** EPOCH 2 STARTS ***/
        /**********************/

        assertEq(mpl.balanceOf(address(mplRewards)), 25_000 * WAD - dTime1_rpt * 10 * WAD / WAD);  // Bob's claimable MPL is still in the contract

        gov.setRewardsDuration(15 days);

        mpl.transfer(address(mplRewards), 40_000 * WAD);

        gov.notifyRewardAmount(40_000 * WAD);

        uint256 rewardRate2 = mplRewards.rewardRate(); // New rewardRate

        assertEq(rewardRate2, uint256(40_000 * WAD) / 15 days);

        hevm.warp(block.timestamp + 1 days);  // Warp to 1 day into the second epoch

        uint256 dTime2_rpt = rewardRate2 * 1 days * WAD / (40 * WAD);  // Reward per token (RPT) for one day of epoch 2 (uses the new rewardRate)

        /*** Ali time = (1 days into epoch 2) pre-exit ***/
        assertRewardsAccounting({
            account:                address(fay),                 // Account for accounting
            totalSupply:            40 * WAD,                     // Ali + Bob stake
            rewardPerTokenStored:   dTime1_rpt,                   // From last epoch
            userRewardPerTokenPaid: dTime1_rpt,                   // Used so Ali can't do multiple claims
            earned:                 dTime2_rpt * 10 * WAD / WAD,  // Time-based calculation (epoch 2 earnings)
            rewards:                0,                            // Not updated yet
            rewardTokenBal:         dTime1_rpt * 10 * WAD / WAD   // Total claimed earnings from pool
        });

        /*** Bob time = (1 days into epoch 2) pre-exit ***/
        assertRewardsAccounting({
            account:                address(fez),                                // Account for accounting
            totalSupply:            40 * WAD,                                    // Ali + Bob stake
            rewardPerTokenStored:   dTime1_rpt,                                  // From last epoch
            userRewardPerTokenPaid: 0,                                           // Used so Ali can't do multiple claims
            earned:                 (dTime1_rpt + dTime2_rpt) * 30 * WAD / WAD,  // Time-based calculation (epoch 1 + epoch 2 earnings)
            rewards:                0,                                           // Not updated yet
            rewardTokenBal:         0                                            // Total claimed earnings from pool
        });

        fay.exit();  // Ali exits at time = (1 days into epoch 2)
        fez.exit();  // Bob exits at time = (1 days into epoch 2)

        /*** Ali time = (1 days into epoch 2) post-exit ***/
        assertRewardsAccounting({
            account:                address(fay),                                // Account for accounting
            totalSupply:            0,                                           // Ali + Bob exited
            rewardPerTokenStored:   dTime1_rpt + dTime2_rpt,                     // Updated on updateReward
            userRewardPerTokenPaid: dTime1_rpt + dTime2_rpt,                     // Used so Ali can't do multiple claims
            earned:                 0,                                           // Time-based calculation and userRewardPerTokenPaid cancel out
            rewards:                0,                                           // Updated on updateReward to earned(), then set to zero on getReward
            rewardTokenBal:         (dTime1_rpt + dTime2_rpt) * 10 * WAD / WAD   // Total claimed earnings from pool over both epochs
        });

        /*** Bob time = (1 days into epoch 2) post-exit ***/
        assertRewardsAccounting({
            account:                address(fez),                                // Account for accounting
            totalSupply:            0,                                           // Ali + Bob exited
            rewardPerTokenStored:   dTime1_rpt + dTime2_rpt,                     // Updated on updateReward
            userRewardPerTokenPaid: dTime1_rpt + dTime2_rpt,                     // Used so Bob can't do multiple claims
            earned:                 0,                                           // Time-based calculation and userRewardPerTokenPaid cancel out
            rewards:                0,                                           // Updated on updateReward to earned(), then set to zero on getReward
            rewardTokenBal:         (dTime1_rpt + dTime2_rpt) * 30 * WAD / WAD   // Total claimed earnings from pool over both epochs
        });
    }
}
