// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "test/TestUtil.sol";
import "test/user/Custodian.sol";
import "./IStakeToken.sol";

contract CustodialTestHelper is TestUtil {

    using SafeMath for uint256;

    function setupFarmingEcosystem() internal {
        setUpGlobals();
        setUpTokens();
        setUpOracles();
        setUpFactories();
        setUpCalcs();
        setUpActors();
        createBalancerPool(100_000 * USD, 10_000 * USD);
        transferBptsToPoolDelegatesAndStakers();
        setUpLiquidityPool();
        setUpMplRewardsFactory();
    }

    function custody_and_transfer(uint256 amt, uint256 custodyAmt1, uint256 custodyAmt2, bool isPfdtStakeAsset, IStakeToken stakeToken) public {
        Custodian custodian1 = new Custodian();  // Custodial contract for FDTs - will start out as liquidity mining but could be broader DeFi eventually
        Custodian custodian2 = new Custodian();  // Custodial contract for FDTs - will start out as liquidity mining but could be broader DeFi eventually

        if (isPfdtStakeAsset) {
            amt         = constrictToRange(amt,         100, 1E9,     true);  // $100 - $1b
            custodyAmt1 = constrictToRange(custodyAmt1,  40, amt / 2, true);  // $40 - half of deposit
            custodyAmt2 = constrictToRange(custodyAmt2,  40, amt / 2, true);  // $40 - half of deposit

            mintFundsAndDepositIntoPool(fay, pool1, amt * USD, amt * USD);
            mintFundsAndDepositIntoPool(fez, pool1, amt * USD, amt * USD);

            pat.setLockupPeriod(address(pool1), 0);

            // Convert all amounts to WAD, USD not needed for the rest of the test
            amt         *= WAD;
            custodyAmt1 *= WAD;
            custodyAmt2 *= WAD;
        } else {
            // Transfer BPTs to the Farmers i.e Fay and Fez. Although both can use interchangeably but to make code consistent chose to use Fay anf Fez. 
            sam.transfer(address(bPool), address(fay), bPool.balanceOf(address(sam)));
            sid.transfer(address(bPool), address(fez), bPool.balanceOf(address(sid)));

            amt         = constrictToRange(amt,         100, bPool.balanceOf(address(fay)), true);  // 100 wei - whole BPT bal (fay and fez have the same BPT balance)
            custodyAmt1 = constrictToRange(custodyAmt1,  40, amt / 2,                       true);  //  40 wei - half of stake
            custodyAmt2 = constrictToRange(custodyAmt2,  40, amt / 2,                       true);  //  40 wei - half of stake

            // Make StakeLocker public and stake tokens
            pat.openStakeLockerToPublic(address(stakeLocker1));

            fay.approve(address(bPool), pool1.stakeLocker(), amt);
            fez.approve(address(bPool), pool1.stakeLocker(), amt);
            fay.stakeTo(                pool1.stakeLocker(), amt);
            fez.stakeTo(                pool1.stakeLocker(), amt);

            pat.setStakeLockerLockupPeriod(address(stakeLocker1), 0);
        }

        // Testing failure modes with Fay
        assertTrue(!fay.try_increaseCustodyAllowance(address(0),              amt));  // P/SL:INVALID_ADDRESS
        assertTrue(!fay.try_increaseCustodyAllowance(address(custodian1),       0));  // P/SL:INVALID_AMT
        assertTrue(!fay.try_increaseCustodyAllowance(address(custodian1), amt + 1));  // P/SL:INSUF_BALANCE
        assertTrue( fay.try_increaseCustodyAllowance(address(custodian1),     amt));  // Fay can custody entire balance

        // Testing state transition and transfers with Fez
        assertEq(stakeToken.custodyAllowance(address(fez), address(custodian1)), 0);
        assertEq(stakeToken.totalCustodyAllowance(address(fez)),                 0);

        fez.increaseCustodyAllowance(address(custodian1), custodyAmt1);

        assertEq(stakeToken.custodyAllowance(address(fez), address(custodian1)), custodyAmt1);  // Fez gives custody to custodian 1
        assertEq(stakeToken.totalCustodyAllowance(address(fez)),                 custodyAmt1);  // Total custody allowance goes up

        fez.increaseCustodyAllowance(address(custodian2), custodyAmt2);

        assertEq(stakeToken.custodyAllowance(address(fez), address(custodian2)),               custodyAmt2);  // Fez gives custody to custodian 2
        assertEq(stakeToken.totalCustodyAllowance(address(fez)),                 custodyAmt1 + custodyAmt2);  // Total custody allowance goes up

        uint256 transferableAmt = amt - custodyAmt1 - custodyAmt2;

        assertEq(stakeToken.balanceOf(address(fez)), amt);
        assertEq(stakeToken.balanceOf(address(fox)),   0);

        assertTrue(!fez.try_transfer(address(stakeToken), address(fox), transferableAmt + 1));  // Fez cannot transfer more than balance - totalCustodyAllowance
        assertTrue( fez.try_transfer(address(stakeToken), address(fox),     transferableAmt));  // Fez can transfer transferableAmt

        assertEq(stakeToken.balanceOf(address(fez)), amt - transferableAmt);
        assertEq(stakeToken.balanceOf(address(fox)),       transferableAmt);
    }

    function custody_and_withdraw(uint256 amt, uint256 custodyAmt, bool isPfdtStakeAsset, IStakeToken stakeToken) public {
        Custodian custodian = new Custodian();

        if (isPfdtStakeAsset) {
            amt        = constrictToRange(amt,        1, 1E9, true);  // $1 - $1b
            custodyAmt = constrictToRange(custodyAmt, 1, amt, true);  // $1 - amt

            mintFundsAndDepositIntoPool(fez, pool1, amt * USD, amt * USD);
            pat.setLockupPeriod(address(pool1), 0);

            amt        *= WAD;
            custodyAmt *= WAD;
        } else {
            // Transfer BPTs to the Farmers i.e Fay and Fez. Although both can use interchangeably but to make it code consistent chosses to use Fay and Fez. 
            sam.transfer(address(bPool), address(fez), bPool.balanceOf(address(sam)));

            amt        = constrictToRange(amt,        1, bPool.balanceOf(address(fez)), true);  // 1 wei - whole BPT bal
            custodyAmt = constrictToRange(custodyAmt, 1, amt,                           true);  // 1 wei - amt

            // Make StakeLocker public and stake tokens
            pat.openStakeLockerToPublic(   address(stakeLocker1));
            fez.approve(address(bPool),    address(stakeLocker1), amt);
            fez.stakeTo(                   address(stakeLocker1), amt);
            pat.setStakeLockerLockupPeriod(address(stakeLocker1),   0);
        }

        assertEq(stakeToken.custodyAllowance(address(fez), address(custodian)), 0);
        assertEq(stakeToken.totalCustodyAllowance(address(fez)),                0);

        fez.increaseCustodyAllowance(address(custodian), custodyAmt);

        assertEq(stakeToken.custodyAllowance(address(fez), address(custodian)), custodyAmt);
        assertEq(stakeToken.totalCustodyAllowance(address(fez)),                custodyAmt);

        uint256 withdrawAmt = amt - custodyAmt;

        assertEq(stakeToken.balanceOf(address(fez)), amt);

        if (isPfdtStakeAsset) {
            make_withdrawable(fez, pool1);

            assertTrue(!fez.try_withdraw(address(stakeToken), toUsd(withdrawAmt) + 1));
            assertTrue( fez.try_withdraw(address(stakeToken),     toUsd(withdrawAmt)));

            assertEq(usdc.balanceOf(address(fez)), toUsd(withdrawAmt));

        } else {
            make_unstakeable(Staker(address(fez)), stakeLocker1);

            assertTrue(!fez.try_unstake(address(stakeToken), withdrawAmt + 1));
            assertTrue( fez.try_unstake(address(stakeToken),     withdrawAmt));
        }

        assertEq(stakeToken.balanceOf(address(fez)), custodyAmt);
    }

    function fdt_transferByCustodian(uint256 amt, uint256 custodyAmt, bool isPfdtStakeAsset, IStakeToken stakeToken) public {
        Custodian custodian = new Custodian();  // Custodial contract for FDTs - will start out as liquidity mining but could be broader DeFi eventually

        if (isPfdtStakeAsset) {
            amt        = constrictToRange(amt,        1, 1E9, true);  // $1 - $1b
            custodyAmt = constrictToRange(custodyAmt, 1, amt, true);  // $1 - deposit

            mintFundsAndDepositIntoPool(fay, pool1, amt * USD, amt * USD);

            amt        *= WAD;
            custodyAmt *= WAD;
        } else {
            // Transfer BPTs to the Farmers i.e Fay and Fez. Although both can use interchangeably but to make it code consistent chosses to use Fay anf Fez. 
            sam.transfer(address(bPool), address(fay), bPool.balanceOf(address(sam)));

            amt        = constrictToRange(amt,        1, bPool.balanceOf(address(fay)), true);  // 1 wei - whole BPT bal
            custodyAmt = constrictToRange(custodyAmt, 1, amt,                           true);  // 1 wei - amt

            // Make StakeLocker public and stake tokens
            pat.openStakeLockerToPublic(address(stakeLocker1));
            fay.approve(address(bPool), address(stakeLocker1), amt);
            fay.stakeTo(                address(stakeLocker1), amt);
        }

        fay.increaseCustodyAllowance(address(custodian), custodyAmt);

        assertEq(stakeToken.custodyAllowance(address(fay), address(custodian)), custodyAmt);  // Fay gives custody to custodian
        assertEq(stakeToken.totalCustodyAllowance(address(fay)),                custodyAmt);  // Total custody allowance goes up

        assertTrue(!custodian.try_transferByCustodian(address(stakeToken), address(fay), address(fox),     custodyAmt));  // P/SL:INVALID_RECEIVER
        assertTrue(!custodian.try_transferByCustodian(address(stakeToken), address(fay), address(fay),              0));  // P/SL:INVALID_AMT
        assertTrue(!custodian.try_transferByCustodian(address(stakeToken), address(fay), address(fay), custodyAmt + 1));  // P/SL:INSUF_ALLOWANCE
        assertTrue( custodian.try_transferByCustodian(address(stakeToken), address(fay), address(fay),     custodyAmt));  // Able to transfer custody amount back

        assertEq(stakeToken.custodyAllowance(address(fay), address(custodian)), 0);  // Custodian allowance has been reduced
        assertEq(stakeToken.totalCustodyAllowance(address(fay)),                0);  // Total custody allowance has been reduced, giving Fay access to funds again
    }

    /****************************/
    /*** LP functions testing ***/
    /****************************/
    function stake_test(bool isPfdtStakeToken, uint256 amt, uint256 stakeAmt, IStakeToken stakeToken) public {
        uint256 start = block.timestamp;

        if (isPfdtStakeToken) {
            mintFundsAndDepositIntoPool(fay, pool1, amt * USD, amt * USD);
        } else {
            setUpForStakeLocker(amt, sam, fay);
        }

        checkDepositOrStakeDate(isPfdtStakeToken, start, stakeToken, fay);

        amt *= WAD;

        assertEq(stakeToken.balanceOf(address(fay)), amt);
        assertEq(mplRewards.balanceOf(address(fay)),   0);
        assertEq(mplRewards.totalSupply(),             0);

        hevm.warp(start + 1 days);  // Warp to ensure no effect on depositDates

        assertTrue(!fay.try_stake(stakeAmt * WAD));  // Can't stake before approval

        fay.increaseCustodyAllowance(address(mplRewards), stakeAmt * WAD);

        assertTrue(!fay.try_stake(0));               // Can't stake zero
        assertTrue( fay.try_stake(stakeAmt * WAD));  // Can stake after approval

        assertEq(stakeToken.balanceOf(address(fay)),            amt);  // PoolFDT balance doesn't change
        assertEq(mplRewards.balanceOf(address(fay)), stakeAmt * WAD);
        assertEq(mplRewards.totalSupply(),           stakeAmt * WAD);

        checkDepositOrStakeDate(isPfdtStakeToken, start, stakeToken, fay);
    }

    function withdraw_test(bool isPfdtStakeToken, uint256 amt, uint256 stakeAmt, IStakeToken stakeToken) public {
        uint256 start = block.timestamp;

        if (isPfdtStakeToken) {
            mintFundsAndDepositIntoPool(fay, pool1, amt * USD, amt * USD);
            assertEq(stakeToken.balanceOf(address(fay)), amt * WAD);
        } else {
            setUpForStakeLocker(amt, sam, fay);
        }

        amt      *= WAD;
        stakeAmt *= WAD;

        fay.increaseCustodyAllowance(address(mplRewards), stakeAmt);
        fay.stake(stakeAmt);

        hevm.warp(start + 1 days);  // Warp to ensure no effect on depositDates

        checkDepositOrStakeDate(isPfdtStakeToken, start, stakeToken, fay);

        assertEq(stakeToken.balanceOf(address(fay)),      amt);  // FDT balance doesn't change
        assertEq(mplRewards.balanceOf(address(fay)), stakeAmt);
        assertEq(mplRewards.totalSupply(),           stakeAmt);

        uint256 currentCustodyAllowance = stakeToken.totalCustodyAllowance(address(fay));

        assertTrue(!fay.try_withdraw(0));         // Can't withdraw zero
        assertTrue( fay.try_withdraw(stakeAmt));  // Can withdraw

        assertEq(stakeToken.totalCustodyAllowance(address(fay)), currentCustodyAllowance - stakeAmt);

        checkDepositOrStakeDate(isPfdtStakeToken, start, stakeToken, fay);

        assertEq(stakeToken.balanceOf(address(fay)), amt);
        assertEq(mplRewards.balanceOf(address(fay)),   0);
        assertEq(mplRewards.totalSupply(),             0);
    }

    /**********************************/
    /*** Rewards accounting testing ***/
    /**********************************/

    function rewards_single_epoch_test(bool isPfdtStakeToken, uint256 amt, IStakeToken stakeToken) public {

        if (isPfdtStakeToken) {
            mintFundsAndDepositIntoPool(fay, pool1, amt * USD, amt * USD);
            mintFundsAndDepositIntoPool(fez, pool1, amt * USD, amt * USD);
            pat.setLockupPeriod(address(pool1), 0);
        } else {
            mint("BPT", address(sam), amt * WAD);
            mint("BPT", address(sid), amt * WAD);
            setUpForStakeLocker(amt, sam, fay);
            setUpForStakeLocker(amt, sid, fez);
        }

        fay.increaseCustodyAllowance(address(mplRewards), amt * WAD);
        fez.increaseCustodyAllowance(address(mplRewards), amt * WAD);
        fay.stake(10 * WAD);

        mpl.transfer(address(mplRewards), 25_000 * WAD);

        gov.setRewardsDuration(30 days);

        gov.notifyRewardAmount(25_000 * WAD);

        uint256 rewardRate = mplRewards.rewardRate();
        uint256 start      = block.timestamp;

        assertEq(rewardRate, uint256(25_000 * WAD) / 30 days);

        assertEq(mpl.balanceOf(address(mplRewards)), 25_000 * WAD);

        /*** Fay time = 0 post-stake ***/
        assertRewardsAccounting({
            account:                address(fay),   // Account for accounting
            totalSupply:            10 * WAD,       // Fay's stake
            rewardPerTokenStored:   0,              // Starting state
            userRewardPerTokenPaid: 0,              // Starting state
            earned:                 0,              // Starting state
            rewards:                0,              // Starting state
            rewardTokenBal:         0               // Starting state
        });

        fay.getReward();  // Get reward at time = 0

        /*** Fay time = (0 days) post-claim ***/
        assertRewardsAccounting({
            account:                address(fay),   // Account for accounting
            totalSupply:            10 * WAD,       // Fay's stake
            rewardPerTokenStored:   0,              // Starting state (getReward has no effect at time = 0)
            userRewardPerTokenPaid: 0,              // Starting state (getReward has no effect at time = 0)
            earned:                 0,              // Starting state (getReward has no effect at time = 0)
            rewards:                0,              // Starting state (getReward has no effect at time = 0)
            rewardTokenBal:         0               // Starting state (getReward has no effect at time = 0)
        });

        hevm.warp(start + 1 days);  // Warp to time = (1 days) (dTime = 1 days)

        // Reward per token (RPT) that was used before fez entered the pool (accrued over dTime = 1 days)
        uint256 dTime1_rpt = rewardRate * 1 days * WAD / (10 * WAD);

        /*** Fay time = (1 days) pre-claim ***/
        assertRewardsAccounting({
            account:                address(fay),                 // Account for accounting
            totalSupply:            10 * WAD,                     // Fay's stake
            rewardPerTokenStored:   0,                            // Not updated yet
            userRewardPerTokenPaid: 0,                            // Not updated yet
            earned:                 dTime1_rpt * 10 * WAD / WAD,  // Time-based calculation
            rewards:                0,                            // Not updated yet
            rewardTokenBal:         0                             // Nothing claimed
        });

        fay.getReward();  // Get reward at time = (1 days)

        /*** Fay time = (1 days) post-claim ***/
        assertRewardsAccounting({
            account:                address(fay),                 // Account for accounting
            totalSupply:            10 * WAD,                     // Fay's stake
            rewardPerTokenStored:   dTime1_rpt,                   // Updated on updateReward
            userRewardPerTokenPaid: dTime1_rpt,                   // Updated on updateReward for 100% ownership in pool after 1hr
            earned:                 0,                            // Time-based calculation and userRewardPerTokenPaid cancel out
            rewards:                0,                            // Updated on updateReward to earned(), then set to zero on getReward
            rewardTokenBal:         dTime1_rpt * 10 * WAD / WAD   // Updated on getReward, account has claimed rewards (equal to original earned() amt at this timestamp))
        });

        fez.stake(10 * WAD);  // Fez stakes 10 FDTs, giving him 50% stake in the pool rewards going forward

        /*** Fez time = (1 days) post-stake ***/
        assertRewardsAccounting({
            account:                address(fez),  // Account for accounting
            totalSupply:            2 * 10 * WAD,  // Fay + Fez stake
            rewardPerTokenStored:   dTime1_rpt,    // Doesn't change since no time has passed
            userRewardPerTokenPaid: dTime1_rpt,    // Used so Fez can't claim past rewards
            earned:                 0,             // Time-based calculation and userRewardPerTokenPaid cancel out, meaning Fez only earns future rewards
            rewards:                0,             // Not updated yet
            rewardTokenBal:         0              // Not updated yet
        });

        hevm.warp(start + 2 days);  // Warp to time = (2 days) (dTime = 1 days)

        // Reward per token (RPT) that was used after Fez entered the pool (accrued over dTime = 1 days, on second day), smaller since supply increased
        uint256 dTime2_rpt = rewardRate * 1 days * WAD / (2 * 10 * WAD);

        /*** Fay time = (2 days) pre-claim ***/
        assertRewardsAccounting({
            account:                address(fay),                 // Account for accounting
            totalSupply:            2 * 10 * WAD,                 // Fay + Fez stake
            rewardPerTokenStored:   dTime1_rpt,                   // Not updated yet
            userRewardPerTokenPaid: dTime1_rpt,                   // Used so Fay can't do multiple claims
            earned:                 dTime2_rpt * 10 * WAD / WAD,  // Fay has not claimed any rewards that have accrued during dTime2
            rewards:                0,                            // Not updated yet
            rewardTokenBal:         dTime1_rpt * 10 * WAD / WAD   // From previous claim
        });

        /*** Fez time = (2 days) pre-claim ***/
        assertRewardsAccounting({
            account:                address(fez),                 // Account for accounting
            totalSupply:            2 * 10 * WAD,                 // Fay + Fez stake
            rewardPerTokenStored:   dTime1_rpt,                   // Not updated yet
            userRewardPerTokenPaid: dTime1_rpt,                   // Used so Fez can't do claims on past rewards
            earned:                 dTime2_rpt * 10 * WAD / WAD,  // Fez has not claimed any rewards that have accrued during dTime2
            rewards:                0,                            // Not updated yet
            rewardTokenBal:         0                             // Not updated yet
        });

        fez.stake(2 * 10 * WAD);  // Fez stakes another 2 * 10 FDTs, giving him 75% stake in the pool rewards going forward

        /*** Fez time = (2 days) post-stake ***/
        assertRewardsAccounting({
            account:                address(fez),                 // Account for accounting
            totalSupply:            4 * 10 * WAD,                 // Fay + Fez stake
            rewardPerTokenStored:   dTime1_rpt + dTime2_rpt,      // Updated on updateReward to snapshot rewardPerToken up to that point
            userRewardPerTokenPaid: dTime1_rpt + dTime2_rpt,      // Used so Fez can't do claims on past rewards
            earned:                 dTime2_rpt * 10 * WAD / WAD,  // Earned updated to reflect all unclaimed earnings pre stake
            rewards:                dTime2_rpt * 10 * WAD / WAD,  // Rewards updated to earnings on updateReward
            rewardTokenBal:         0                             // Not updated yet
        });

        hevm.warp(start + 2 days + 1 hours);  // Warp to time = (2 days + 1 hours) (dTime = 1 hours)

        uint256 dTime3_rpt = rewardRate * 1 hours * WAD / (4 * 10 * WAD);  // Reward per token (RPT) that was used after Fez staked more into the pool (accrued over dTime = 1 hours)

        /*** Fay time = (2 days + 1 hours) pre-claim ***/
        assertRewardsAccounting({
            account:                address(fay),                                // Account for accounting
            totalSupply:            4 * 10 * WAD,                                // Fay + Fez stake
            rewardPerTokenStored:   dTime1_rpt + dTime2_rpt,                     // Not updated yet
            userRewardPerTokenPaid: dTime1_rpt,                                  // Used so Fay can't do multiple claims
            earned:                 (dTime2_rpt + dTime3_rpt) * 10 * WAD / WAD,  // Fay has not claimed any rewards that have accrued during dTime2 or dTime3
            rewards:                0,                                           // Not updated yet
            rewardTokenBal:         dTime1_rpt * 10 * WAD / WAD                  // From previous claim
        });

        /*** Fez time = (2 days + 1 hours) pre-claim ***/
        assertRewardsAccounting({
            account:                address(fez),                                           // Account for accounting
            totalSupply:            40 * WAD,                                               // Fay + Fez stake
            rewardPerTokenStored:   dTime1_rpt + dTime2_rpt,                                // Not updated yet
            userRewardPerTokenPaid: dTime1_rpt + dTime2_rpt,                                // Used so Fez can't do claims on past rewards
            earned:                 (dTime2_rpt * 10 * WAD + dTime3_rpt * 30 * WAD) / WAD,  // Fez's earnings since he entered the pool
            rewards:                dTime2_rpt * 10 * WAD / WAD,                            // Rewards updated to reflect all unclaimed earnings pre stake
            rewardTokenBal:         0                                                       // Not updated yet
        });

        fez.getReward();  // Get reward at time = (2 days + 1 hours)

        /*** Fez time = (2 days + 1 hours) post-claim ***/
        assertRewardsAccounting({
            account:                address(fez),                                          // Account for accounting
            totalSupply:            40 * WAD,                                              // Fay + Fez stake
            rewardPerTokenStored:   dTime1_rpt + dTime2_rpt + dTime3_rpt,                  // Updated on updateReward
            userRewardPerTokenPaid: dTime1_rpt + dTime2_rpt + dTime3_rpt,                  // Used so Fez can't do multiple claims
            earned:                 0,                                                     // Time-based calculation and userRewardPerTokenPaid cancel out
            rewards:                0,                                                     // Updated on updateReward to earned(), then set to zero on getReward
            rewardTokenBal:         (dTime2_rpt * 10 * WAD + dTime3_rpt * 30 * WAD) / WAD  // Updated on getReward, account has claimed rewards (equal to original earned() amt at this timestamp))
        });

        fez.getReward();  // Try double claim

        /*** Fez time = (2 days + 1 hours) post-claim (ASSERT NOTHING CHANGES) ***/
        assertRewardsAccounting({
            account:                address(fez),                                          // Doesn't change
            totalSupply:            40 * WAD,                                              // Doesn't change
            rewardPerTokenStored:   dTime1_rpt + dTime2_rpt + dTime3_rpt,                  // Doesn't change
            userRewardPerTokenPaid: dTime1_rpt + dTime2_rpt + dTime3_rpt,                  // Doesn't change
            earned:                 0,                                                     // Doesn't change
            rewards:                0,                                                     // Doesn't change
            rewardTokenBal:         (dTime2_rpt * 10 * WAD + dTime3_rpt * 30 * WAD) / WAD  // Doesn't change
        });

        fay.withdraw(5 * WAD);  // Fay withdraws 5 * WAD at time = (2 days + 1 hours)

        /*** Fay time = (2 days + 1 hours) pre-claim ***/
        assertRewardsAccounting({
            account:                address(fay),                                // Account for accounting
            totalSupply:            35 * WAD,                                    // Fay + Fez stake, lower now that Fay withdrew
            rewardPerTokenStored:   dTime1_rpt + dTime2_rpt + dTime3_rpt,        // From Fez's update
            userRewardPerTokenPaid: dTime1_rpt + dTime2_rpt + dTime3_rpt,        // Used so Fay can't claim past earnings
            earned:                 (dTime2_rpt + dTime3_rpt) * 10 * WAD / WAD,  // Fay has not claimed any rewards that have accrued during dTime2 and dTime3
            rewards:                (dTime2_rpt + dTime3_rpt) * 10 * WAD / WAD,  // Updated on updateReward to earned()
            rewardTokenBal:         dTime1_rpt * 10 * WAD / WAD                  // From previous claim
        });

        hevm.warp(start + 3 days + 1 hours);  // Warp to time = (3 days + 1 hours) (dTime = 1 days)

        uint256 dTime4_rpt = rewardRate * 1 days * WAD / (35 * WAD);  // Reward per token (RPT) that was used after Fay withdrew from the pool (accrued over dTime = 1 days)

        /*** Fay time = (3 days + 1 hours) pre-exit ***/
        assertRewardsAccounting({
            account:                address(fay),                                                         // Account for accounting
            totalSupply:            35 * WAD,                                                             // Fay + Fez stake
            rewardPerTokenStored:   dTime1_rpt + dTime2_rpt + dTime3_rpt,                                 // Not updated yet
            userRewardPerTokenPaid: dTime1_rpt + dTime2_rpt + dTime3_rpt,                                 // Used so Fay can't do multiple claims
            earned:                 ((dTime2_rpt + dTime3_rpt) * 10 * WAD + dTime4_rpt * 5 * WAD) / WAD,  // Fay has not claimed any rewards that have accrued during dTime2, dTime3 and dTime4
            rewards:                (dTime2_rpt + dTime3_rpt) * 10 * WAD / WAD,                           // Not updated yet
            rewardTokenBal:         dTime1_rpt * 10 * WAD / WAD                                           // From previous claim
        });

        /*** Fez time = (2 days + 1 hours) pre-exit ***/
        assertRewardsAccounting({
            account:                address(fez),                                          // Account for accounting
            totalSupply:            35 * WAD,                                              // Fay + Fez stake
            rewardPerTokenStored:   dTime1_rpt + dTime2_rpt + dTime3_rpt,                  // Not updated yet
            userRewardPerTokenPaid: dTime1_rpt + dTime2_rpt + dTime3_rpt,                  // Used so Fez can't do multiple claims
            earned:                 dTime4_rpt * 30 * WAD / WAD,                           // Fez has not claimed any rewards that have accrued during dTime4
            rewards:                0,                                                     // Not updated yet
            rewardTokenBal:         (dTime2_rpt * 10 * WAD + dTime3_rpt * 30 * WAD) / WAD  // From previous claim
        });

        fay.exit();  // Fay exits at time = (3 days + 1 hours)
        fez.exit();  // Fez exits at time = (3 days + 1 hours)

        /*** Fay time = (3 days + 1 hours) post-exit ***/
        assertRewardsAccounting({
            account:                address(fay),                                                                     // Account for accounting
            totalSupply:            0,                                                                                // Fay + Fez withdrew all stake
            rewardPerTokenStored:   dTime1_rpt + dTime2_rpt + dTime3_rpt + dTime4_rpt,                                // Updated on updateReward
            userRewardPerTokenPaid: dTime1_rpt + dTime2_rpt + dTime3_rpt + dTime4_rpt,                                // Used so Fay can't do multiple claims
            earned:                 0,                                                                                // Time-based calculation and userRewardPerTokenPaid cancel out
            rewards:                0,                                                                                // Updated on updateReward to earned(), then set to zero on getReward
            rewardTokenBal:         ((dTime1_rpt + dTime2_rpt + dTime3_rpt) * 10 ether + dTime4_rpt * 5 ether) / WAD  // Total earnings from pool (using ether to avoid stack too deep)
        });

        /*** Fez time = (2 days + 1 hours) post-exit ***/
        assertRewardsAccounting({
            account:                address(fez),                                                         // Account for accounting
            totalSupply:            0,                                                                    // Fay + Fez withdrew all stake
            rewardPerTokenStored:   dTime1_rpt + dTime2_rpt + dTime3_rpt + dTime4_rpt,                    // Updated on updateReward
            userRewardPerTokenPaid: dTime1_rpt + dTime2_rpt + dTime3_rpt + dTime4_rpt,                    // Used so Fez can't do multiple claims
            earned:                 0,                                                                    // Time-based calculation and userRewardPerTokenPaid cancel out
            rewards:                0,                                                                    // Updated on updateReward to earned(), then set to zero on getReward
            rewardTokenBal:         (dTime2_rpt * 10 ether + (dTime3_rpt + dTime4_rpt) * 30 ether) / WAD  // Total earnings from pool (using ether to avoid stack too deep)
        });
    }

    function rewards_multi_epoch_test(bool isPfdtStakeToken, uint256 amt, IStakeToken stakeToken) public {
        
        if (isPfdtStakeToken) {
            mintFundsAndDepositIntoPool(fay, pool1, amt * USD, amt * USD);
            mintFundsAndDepositIntoPool(fez, pool1, amt * USD, amt * USD);
            pat.setLockupPeriod(address(pool1), 0);
        } else {
            mint("BPT", address(sam), amt * WAD);
            mint("BPT", address(sid), amt * WAD);
            setUpForStakeLocker(amt, sam, fay);
            setUpForStakeLocker(amt, sid, fez);
        }
        
        fay.increaseCustodyAllowance(address(mplRewards), amt * WAD);
        fez.increaseCustodyAllowance(address(mplRewards), amt * WAD);

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

        /*** Fay time = (30 days) pre-claim ***/
        assertRewardsAccounting({
            account:                address(fay),                 // Account for accounting
            totalSupply:            40 * WAD,                     // Fay + Fez stake
            rewardPerTokenStored:   0,                            // Not updated yet
            userRewardPerTokenPaid: 0,                            // Not updated yet
            earned:                 dTime1_rpt * 10 * WAD / WAD,  // Time-based calculation
            rewards:                0,                            // Not updated yet
            rewardTokenBal:         0                             // Total claimed earnings from pool
        });

        /*** Fez time = (30 days) pre-claim ***/
        assertRewardsAccounting({
            account:                address(fez),                 // Account for accounting
            totalSupply:            40 * WAD,                     // Fay + Fez stake
            rewardPerTokenStored:   0,                            // Not updated yet
            userRewardPerTokenPaid: 0,                            // Not updated yet
            earned:                 dTime1_rpt * 30 * WAD / WAD,  // Time-based calculation
            rewards:                0,                            // Not updated yet
            rewardTokenBal:         0                             // Total claimed earnings from pool
        });

        fay.getReward();  // Fay claims all rewards for epoch 1

        /*** Fay time = (30 days) post-claim ***/
        assertRewardsAccounting({
            account:                address(fay),                 // Account for accounting
            totalSupply:            40 * WAD,                     // Fay + Fez stake
            rewardPerTokenStored:   dTime1_rpt,                   // Updated on updateReward
            userRewardPerTokenPaid: dTime1_rpt,                   // Used so Fay can't do multiple claims
            earned:                 0,                            // Time-based calculation and userRewardPerTokenPaid cancel out
            rewards:                0,                            // Updated on updateReward to earned(), then set to zero on getReward
            rewardTokenBal:         dTime1_rpt * 10 * WAD / WAD   // Total claimed earnings from pool
        });

        assertEq(mplRewards.lastUpdateTime(),           start + 30 days);
        assertEq(mplRewards.lastTimeRewardApplicable(), start + 30 days);

        hevm.warp(periodFinish + 1 days);  // Warp another day after the epoch is finished

        assertEq(mplRewards.lastUpdateTime(),           start + 30 days);  // Doesn't change
        assertEq(mplRewards.lastTimeRewardApplicable(), start + 30 days);  // Doesn't change

        /*** Fay time = (31 days) pre-claim (ASSERT NOTHING CHANGES DUE TO EPOCH BEING OVER) ***/
        assertRewardsAccounting({
            account:                address(fay),                 // Doesn't change
            totalSupply:            40 * WAD,                     // Doesn't change
            rewardPerTokenStored:   dTime1_rpt,                   // Doesn't change
            userRewardPerTokenPaid: dTime1_rpt,                   // Doesn't change
            earned:                 0,                            // Doesn't change
            rewards:                0,                            // Doesn't change
            rewardTokenBal:         dTime1_rpt * 10 * WAD / WAD   // Doesn't change
        });

        fay.getReward();  // Fay claims rewards, but epoch 1 is finished

        /*** Fay time = (31 days) post-claim (ASSERT NOTHING CHANGES DUE TO EPOCH BEING OVER) ***/
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

        assertEq(mpl.balanceOf(address(mplRewards)), 25_000 * WAD - dTime1_rpt * 10 * WAD / WAD);  // Fez's claimable MPL is still in the contract

        gov.setRewardsDuration(15 days);

        mpl.transfer(address(mplRewards), 40_000 * WAD);

        gov.notifyRewardAmount(40_000 * WAD);

        uint256 rewardRate2 = mplRewards.rewardRate();  // New rewardRate

        assertEq(rewardRate2, uint256(40_000 * WAD) / 15 days);

        hevm.warp(block.timestamp + 1 days);  // Warp to 1 day into the second epoch

        uint256 dTime2_rpt = rewardRate2 * 1 days * WAD / (40 * WAD);  // Reward per token (RPT) for one day of epoch 2 (uses the new rewardRate)

        /*** Fay time = (1 days into epoch 2) pre-exit ***/
        assertRewardsAccounting({
            account:                address(fay),                 // Account for accounting
            totalSupply:            40 * WAD,                     // Fay + Fez stake
            rewardPerTokenStored:   dTime1_rpt,                   // From last epoch
            userRewardPerTokenPaid: dTime1_rpt,                   // Used so Fay can't do multiple claims
            earned:                 dTime2_rpt * 10 * WAD / WAD,  // Time-based calculation (epoch 2 earnings)
            rewards:                0,                            // Not updated yet
            rewardTokenBal:         dTime1_rpt * 10 * WAD / WAD   // Total claimed earnings from pool
        });

        /*** Fez time = (1 days into epoch 2) pre-exit ***/
        assertRewardsAccounting({
            account:                address(fez),                                // Account for accounting
            totalSupply:            40 * WAD,                                    // Fay + Fez stake
            rewardPerTokenStored:   dTime1_rpt,                                  // From last epoch
            userRewardPerTokenPaid: 0,                                           // Used so Fay can't do multiple claims
            earned:                 (dTime1_rpt + dTime2_rpt) * 30 * WAD / WAD,  // Time-based calculation (epoch 1 + epoch 2 earnings)
            rewards:                0,                                           // Not updated yet
            rewardTokenBal:         0                                            // Total claimed earnings from pool
        });

        fay.exit();  // Fay exits at time = (1 days into epoch 2)
        fez.exit();  // Fez exits at time = (1 days into epoch 2)

        /*** Fay time = (1 days into epoch 2) post-exit ***/
        assertRewardsAccounting({
            account:                address(fay),                                // Account for accounting
            totalSupply:            0,                                           // Fay + Fez exited
            rewardPerTokenStored:   dTime1_rpt + dTime2_rpt,                     // Updated on updateReward
            userRewardPerTokenPaid: dTime1_rpt + dTime2_rpt,                     // Used so Fay can't do multiple claims
            earned:                 0,                                           // Time-based calculation and userRewardPerTokenPaid cancel out
            rewards:                0,                                           // Updated on updateReward to earned(), then set to zero on getReward
            rewardTokenBal:         (dTime1_rpt + dTime2_rpt) * 10 * WAD / WAD   // Total claimed earnings from pool over both epochs
        });

        /*** Fez time = (1 days into epoch 2) post-exit ***/
        assertRewardsAccounting({
            account:                address(fez),                                // Account for accounting
            totalSupply:            0,                                           // Fay + Fez exited
            rewardPerTokenStored:   dTime1_rpt + dTime2_rpt,                     // Updated on updateReward
            userRewardPerTokenPaid: dTime1_rpt + dTime2_rpt,                     // Used so Fez can't do multiple claims
            earned:                 0,                                           // Time-based calculation and userRewardPerTokenPaid cancel out
            rewards:                0,                                           // Updated on updateReward to earned(), then set to zero on getReward
            rewardTokenBal:         (dTime1_rpt + dTime2_rpt) * 30 * WAD / WAD   // Total claimed earnings from pool over both epochs
        });
    } 

    /************************/
    /** Internal Functions **/
    /************************/

    function setUpForStakeLocker(uint256 amt, Staker staker, Farmer farmer) internal {
        staker.transfer(address(bPool), address(farmer), bPool.balanceOf(address(staker)));
        if (!stakeLocker1.openToPublic()) {
            pat.openStakeLockerToPublic(address(stakeLocker1));
        }
        farmer.approve(address(bPool), address(stakeLocker1), amt * WAD);
        farmer.stakeTo(                address(stakeLocker1), amt * WAD);
    }

    function checkDepositOrStakeDate(bool isPfdtStakeToken, uint256 date, IStakeToken stakeToken, Farmer farmer) internal {
        if (isPfdtStakeToken) {
            assertEq(stakeToken.depositDate(address(farmer)),     date);  // Has not changed
            assertEq(stakeToken.depositDate(address(mplRewards)),    0);  // Has not changed
        } else {
            assertEq(stakeToken.stakeDate(address(farmer)),     date);  // Has not changed
            assertEq(stakeToken.stakeDate(address(mplRewards)),    0);  // Has not changed
        }
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
}
