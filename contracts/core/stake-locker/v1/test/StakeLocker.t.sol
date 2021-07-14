// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import { IERC20 } from "../../../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { TestUtil } from "../../../../test/TestUtil.sol";

contract StakeLockerTest is TestUtil {

    function setUp() public {
        setUpGlobals();
        setUpTokens();
        setUpOracles();
        setUpFactories();
        setUpCalcs();
        setUpActors();
        setUpBalancerPoolForStakers();
        setUpLiquidityPool();
        createLoan();
    }

    function getNewStakeDate(address account, uint256 amt) public view returns (uint256 newStakeDate) {
        // Keeping original test logic different from counterpart code to ensure continued expected behavior (for now)
        uint256 prevDate = stakeLocker1.stakeDate(account);
        if (prevDate == uint256(0)) {
            newStakeDate = block.timestamp;
        } else {
            uint256 dTime = block.timestamp - prevDate;
            newStakeDate  = prevDate + (dTime * amt / (stakeLocker1.balanceOf(account) + amt));  // stakeDate + (now - stakeDate) * (amt / (balance + amt))
        }
    }

    function makePublicAndStake(uint256 stakeAmount) internal {
        // Make StakeLocker public and stake tokens
        pat.openStakeLockerToPublic(address(stakeLocker1));
        sam.approve(address(bPool), address(stakeLocker1), stakeAmount);
        sam.stake(address(stakeLocker1), stakeAmount);
    }

    function populateStakeLockerPreState(
        TestObj memory stakeLockerBal,
        TestObj memory fdtTotalSupply,
        TestObj memory stakerBPTBal,
        TestObj memory stakerFDTBal,
        TestObj memory stakerStakeDate
    )
        internal
        view
    {
        stakeLockerBal.pre  = bPool.balanceOf(address(stakeLocker1));
        fdtTotalSupply.pre  = stakeLocker1.totalSupply();
        stakerBPTBal.pre    = bPool.balanceOf(address(sam));
        stakerFDTBal.pre    = stakeLocker1.balanceOf(address(sam));
        stakerStakeDate.pre = stakeLocker1.stakeDate(address(sam));
    }

    function populateStakeLockerPostState(
        TestObj memory stakeLockerBal,
        TestObj memory fdtTotalSupply,
        TestObj memory stakerBPTBal,
        TestObj memory stakerFDTBal,
        TestObj memory stakerStakeDate
    )
        internal
        view
    {
        stakeLockerBal.post  = bPool.balanceOf(address(stakeLocker1));
        fdtTotalSupply.post  = stakeLocker1.totalSupply();
        stakerBPTBal.post    = bPool.balanceOf(address(sam));
        stakerFDTBal.post    = stakeLocker1.balanceOf(address(sam));
        stakerStakeDate.post = stakeLocker1.stakeDate(address(sam));
    }

    function test_stake_to_measure_effect_on_stake_date(uint256 initialStake, uint256 additionalStake, uint256 transferStake, uint256 warpTime) external {
        TestObj memory stakeLockerBal;   // StakeLocker total balance of BPTs
        TestObj memory fdtTotalSupply;   // Total Supply of FDTs
        TestObj memory stakerBPTBal;     // Staker Balancer Pool BPT balance
        TestObj memory stakerFDTBal;     // Staker StakeLocker FDT balance
        TestObj memory stakerStakeDate;  // Staker stakeDate

        uint256 bptMin = WAD / 10_000_000;
        initialStake    = constrictToRange(initialStake, bptMin, (bPool.balanceOf(address(sam)) / 2) - 1, true);  // 12.5 WAD max, 1/10m WAD min, or zero (min is roughly equal to 10 cents) (non-zero)
        additionalStake = constrictToRange(additionalStake, bptMin, (bPool.balanceOf(address(sam)) / 2) - 1, true);  // 12.5 WAD max, 1/10m WAD min, or zero (min is roughly equal to 10 cents) (non-zero)
        transferStake   = constrictToRange(transferStake, bptMin, bPool.balanceOf(address(sid)), true);
        warpTime        = constrictToRange(warpTime, 1 days, 365 days, true);

        pat.setAllowlist(address(stakeLocker1), address(sam), true);
        pat.setAllowlist(address(stakeLocker1), address(sid), true);
        sam.approve(address(bPool), address(stakeLocker1), uint256(-1));
        sid.approve(address(bPool), address(stakeLocker1), uint256(-1));
        pat.setStakeLockerLockupPeriod(address(stakeLocker1), 0);

        uint256 startDate = block.timestamp;

        populateStakeLockerPreState(stakeLockerBal, fdtTotalSupply, stakerBPTBal, stakerFDTBal, stakerStakeDate);
        sam.stake(address(stakeLocker1), initialStake);
        populateStakeLockerPostState(stakeLockerBal, fdtTotalSupply, stakerBPTBal, stakerFDTBal, stakerStakeDate);

        assertEq(stakeLockerBal.post, stakeLockerBal.pre + initialStake, "stakeLockerBal  = previous + initialStake");
        assertEq(fdtTotalSupply.post, fdtTotalSupply.pre + initialStake, "fdtTotalSupply  = previous + initialStake");
        assertEq(stakerBPTBal.post, stakerBPTBal.pre - initialStake,     "stakerBPTBal    = previous - initialStake");
        assertEq(stakerFDTBal.post, stakerFDTBal.pre + initialStake,     "stakerFDTBal    = previous + initialStake");
        assertEq(stakerStakeDate.post, startDate,                        "stakerStakeDate = current block timestamp");

        // Warp into the future and stake again
        hevm.warp(startDate + warpTime);
        uint256 newStakeDate = getNewStakeDate(address(sam), additionalStake);

        populateStakeLockerPreState(stakeLockerBal, fdtTotalSupply, stakerBPTBal, stakerFDTBal, stakerStakeDate);
        sam.stake(address(stakeLocker1), additionalStake);
        populateStakeLockerPostState(stakeLockerBal, fdtTotalSupply, stakerBPTBal, stakerFDTBal, stakerStakeDate);

        assertEq(stakeLockerBal.post, stakeLockerBal.pre + additionalStake, "stakeLockerBal  = previous + additionalStake");
        assertEq(fdtTotalSupply.post, fdtTotalSupply.pre + additionalStake, "fdtTotalSupply  = previous + additionalStake");
        assertEq(stakerBPTBal.post, stakerBPTBal.pre - additionalStake,     "stakerBPTBal    = previous - additionalStake");
        assertEq(stakerFDTBal.post, stakerFDTBal.pre + additionalStake,     "stakerFDTBal    = previous + additionalStake");
        assertEq(stakerStakeDate.post, newStakeDate,                        "stakerStakeDate = expected newStakeDate");

        // Warp into the future and receive an FDT transfer
        hevm.warp(startDate + warpTime);
        newStakeDate = getNewStakeDate(address(sam), transferStake);

        populateStakeLockerPreState(stakeLockerBal, fdtTotalSupply, stakerBPTBal, stakerFDTBal, stakerStakeDate);
        sid.stake(address(stakeLocker1), transferStake);
        sid.transfer(address(stakeLocker1), address(sam), transferStake);
        populateStakeLockerPostState(stakeLockerBal, fdtTotalSupply, stakerBPTBal, stakerFDTBal, stakerStakeDate);

        assertEq(stakeLockerBal.post, stakeLockerBal.pre + transferStake, "stakeLockerBal  = previous + transferStake");
        assertEq(fdtTotalSupply.post, fdtTotalSupply.pre + transferStake, "fdtTotalSupply  = previous + transferStake");
        assertEq(stakerBPTBal.post, stakerBPTBal.pre,                     "stakerBPTBal    = previous");
        assertEq(stakerFDTBal.post, stakerFDTBal.pre + transferStake,     "stakerFDTBal    = previous + transferStake");
        assertEq(stakerStakeDate.post, newStakeDate,                      "stakerStakeDate = expected newStakeDate");
    }

    function test_stake_paused() public {
        pat.setAllowlist(address(stakeLocker1), address(sam), true);
        sam.approve(address(bPool), address(stakeLocker1), 20 * WAD);

        // Pause StakeLocker and attempt stake()
        assertTrue( pat.try_pause(address(stakeLocker1)));
        assertTrue(!sam.try_stake(address(stakeLocker1), 10 * WAD));
        assertEq(stakeLocker1.balanceOf(address(sam)),    0 * WAD);

        // Unpause StakeLocker and stake()
        assertTrue(pat.try_unpause(address(stakeLocker1)));
        assertTrue(sam.try_stake(address(stakeLocker1), 10 * WAD));
        assertEq(stakeLocker1.balanceOf(address(sam)),  10 * WAD);

        // Pause protocol and attempt to stake()
        assertTrue( emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!sam.try_stake(address(stakeLocker1), 10 * WAD));
        assertEq(stakeLocker1.balanceOf(address(sam)),   10 * WAD);

        // Unpause protocol and stake()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(sam.try_stake(address(stakeLocker1), 10 * WAD));
        assertEq(stakeLocker1.balanceOf(address(sam)),  20 * WAD);
    }

    function test_stake() public {
        uint256 startDate = block.timestamp;

        assertTrue(!sam.try_stake(address(stakeLocker1),   25 * WAD));  // Hasn't approved BPTs
        sam.approve(address(bPool), address(stakeLocker1), 25 * WAD);

        assertTrue(!sam.try_stake(address(stakeLocker1),   25 * WAD));  // Isn't yet allowlisted

        pat.setAllowlist(address(stakeLocker1), address(sam), true);

        // Check whether PD is allowed to transferFrom or not.
        assertEq(stakeLocker1.balanceOf(address(pat)),   50 * WAD);
        pat.approve(address(stakeLocker1), address(sam), 50 * WAD);
        assertTrue(!sam.try_transferFrom(address(stakeLocker1), address(pat), address(sam), 50 * WAD));

        assertEq(bPool.balanceOf(address(sam)),          25 * WAD);
        assertEq(bPool.balanceOf(address(stakeLocker1)), 50 * WAD);  // PD stake
        assertEq(stakeLocker1.totalSupply(),             50 * WAD);
        assertEq(stakeLocker1.balanceOf(address(sam)),          0);
        assertEq(stakeLocker1.stakeDate(address(sam)),          0);

        assertTrue(sam.try_stake(address(stakeLocker1), 25 * WAD));

        assertEq(bPool.balanceOf(address(sam)),                 0);
        assertEq(bPool.balanceOf(address(stakeLocker1)), 75 * WAD);  // PD + Staker stake
        assertEq(stakeLocker1.totalSupply(),             75 * WAD);
        assertEq(stakeLocker1.balanceOf(address(sam)),   25 * WAD);
        assertEq(stakeLocker1.stakeDate(address(sam)),  startDate);

        sid.approve(address(bPool), address(stakeLocker1), 25 * WAD);

        assertTrue(!sid.try_stake(address(stakeLocker1), 25 * WAD));  // Isn't allowlisted

        // Open StakeLocker to public
        assertTrue(!stakeLocker1.openToPublic());
        assertTrue(!pam.try_openStakeLockerToPublic(address(stakeLocker1)));
        assertTrue( pat.try_openStakeLockerToPublic(address(stakeLocker1)));
        assertTrue( stakeLocker1.openToPublic());
        assertTrue(!stakeLocker1.allowed(address(sid)));  // Sid is not an allowed Staker, but StakeLocker is now open to public

        assertEq(bPool.balanceOf(address(sid)),          25 * WAD);
        assertEq(bPool.balanceOf(address(stakeLocker1)), 75 * WAD);  // PD stake
        assertEq(stakeLocker1.totalSupply(),             75 * WAD);
        assertEq(stakeLocker1.balanceOf(address(sid)),          0);
        assertEq(stakeLocker1.stakeDate(address(sid)),          0);

        assertTrue(sid.try_stake(address(stakeLocker1), 25 * WAD));

        assertEq(bPool.balanceOf(address(sid)),                  0);
        assertEq(bPool.balanceOf(address(stakeLocker1)), 100 * WAD);  // PD + Staker stake
        assertEq(stakeLocker1.totalSupply(),             100 * WAD);
        assertEq(stakeLocker1.balanceOf(address(sid)),    25 * WAD);
        assertEq(stakeLocker1.stakeDate(address(sid)),   startDate);
    }

    function test_withdrawFunds_paused() public {
        // Make StakeLocker public and stake tokens
        pat.openStakeLockerToPublic(address(stakeLocker1));
        sam.approve(address(bPool), address(stakeLocker1), 25 * WAD);
        sam.stake(address(stakeLocker1), 25 * WAD);

        // Pause protocol and attempt withdrawFunds()
        assertTrue( emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!sam.try_withdrawFunds(address(stakeLocker1)));

        // Unpause protocol and withdrawFunds()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(sam.try_withdrawFunds(address(stakeLocker1)));
    }

    function test_unstake_cooldown() public {
        makePublicAndStake(15 * WAD);

        hevm.warp(block.timestamp + stakeLocker1.lockupPeriod());  // Warp to end of lockup for test

        gov.setStakerCooldownPeriod(10 days);

        uint256 amt = 5 * WAD;  // 1/3 of stake so unstake can happen thrice

        uint256 start = block.timestamp;

        assertTrue(!sam.try_unstake(address(stakeLocker1), amt),    "Should fail to unstake 10 WAD because account has to intendToWithdraw");
        assertTrue( sam.try_intendToUnstake(address(stakeLocker1)), "Failed to intend to unstake");
        assertEq(stakeLocker1.unstakeCooldown(address(sam)), start);
        assertTrue(!sam.try_unstake(address(stakeLocker1), amt),    "Should fail to unstake before cooldown period has passed");

        // Just before cooldown ends
        hevm.warp(start + globals.stakerCooldownPeriod() - 1);
        assertTrue(!sam.try_unstake(address(stakeLocker1), amt), "Should fail to unstake before cooldown period has passed");

        // Right when cooldown ends
        hevm.warp(start + globals.stakerCooldownPeriod());
        assertTrue(sam.try_unstake(address(stakeLocker1), amt), "Should be able to unstake during unstake window");

        // Still within Staker unstake window
        hevm.warp(start + globals.stakerCooldownPeriod() + 1);
        assertTrue(sam.try_unstake(address(stakeLocker1), amt), "Should be able to unstake funds again during cooldown window");

        // Second after Staker unstake window ends
        hevm.warp(start + globals.stakerCooldownPeriod() + globals.stakerUnstakeWindow() + 1);
        assertTrue(!sam.try_unstake(address(stakeLocker1), amt), "Should fail to unstake funds because now past unstake window");

        uint256 newStart = block.timestamp;

        // Intend to unstake
        assertTrue(sam.try_intendToUnstake(address(stakeLocker1)), "Failed to intend to unstake");

        // After cooldown ends but after unstake window
        hevm.warp(newStart + globals.stakerCooldownPeriod() + globals.stakerUnstakeWindow() + 1);
        assertTrue(!sam.try_unstake(address(stakeLocker1), amt), "Should fail to unstake after unstake window has passed");

        // Last second of Staker unstake window
        hevm.warp(newStart + globals.stakerCooldownPeriod() + globals.stakerUnstakeWindow());
        assertTrue(sam.try_unstake(address(stakeLocker1), amt), "Should be able to unstake during unstake window");
    }

    function test_stake_transfer_paused() public {
        makePublicAndStake(25 * WAD);
        pat.setStakeLockerLockupPeriod(address(stakeLocker1), 0);

        // Pause protocol and attempt to transfer FDTs
        assertTrue( emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!sam.try_transfer(address(stakeLocker1), address(leo), 1 * WAD));

        // Unpause protocol and transfer FDTs
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(sam.try_transfer(address(stakeLocker1), address(leo), 1 * WAD));
    }

    function test_stake_transfer_lockup_period(uint256 stakeAmount) public {
        uint256 startDate = block.timestamp;
        stakeAmount = constrictToRange(stakeAmount, 1 wei, bPool.balanceOf(address(sam)), true);

        makePublicAndStake(stakeAmount);

        // Will fail because lockup period hasn't passed yet
        assertTrue(!sam.try_transfer(address(stakeLocker1), address(sid), stakeAmount));

        // Warp to just before lockup period ends
        hevm.warp(startDate + pool1.lockupPeriod() - 1);
        assertTrue(!sam.try_transfer(address(stakeLocker1), address(sid), stakeAmount));

        // Warp to after lockup period and transfer
        hevm.warp(startDate + stakeLocker1.lockupPeriod());
        uint256 newStakeDate = getNewStakeDate(address(sid), stakeAmount);
        assertTrue(sam.try_transfer(address(stakeLocker1), address(sid), stakeAmount));

        // Check balances and deposit dates are correct
        assertEq(stakeLocker1.balanceOf(address(sam)), 0);
        assertEq(stakeLocker1.balanceOf(address(sid)), stakeAmount);
        assertEq(stakeLocker1.stakeDate(address(sam)), startDate);     // Stays the same
        assertEq(stakeLocker1.stakeDate(address(sid)), newStakeDate);  // Gets updated
    }

    function test_stake_transfer_recipient_withdrawing() public {
        uint256 start = block.timestamp;
        uint256 stakeAmount = 25 * WAD;

        makePublicAndStake(stakeAmount);
        pat.setStakeLockerLockupPeriod(address(stakeLocker1), 0);

        sid.approve(address(bPool), address(stakeLocker1), stakeAmount);
        sid.stake(address(stakeLocker1), stakeAmount);

        // Staker 1 initiates unstake
        assertTrue(sid.try_intendToUnstake(address(stakeLocker1)));
        assertEq(stakeLocker1.unstakeCooldown(address(sid)), start);

        // Staker 2 fails to transfer to Staker 1 that is currently unstaking
        assertTrue(!sam.try_transfer(address(stakeLocker1), address(sid), stakeAmount));
        hevm.warp(start + globals.stakerCooldownPeriod() + globals.stakerUnstakeWindow());  // Very end of Staker unstake window
        assertTrue(!sam.try_transfer(address(stakeLocker1), address(sid), stakeAmount));

        // Staker 2 successfully transfers to Staker 1 that is now outside unstake window
        hevm.warp(start + globals.stakerCooldownPeriod() + globals.stakerUnstakeWindow() + 1);  // Second after Staker unstake window ends
        uint256 newStakeDate = getNewStakeDate(address(sid), stakeAmount);
        assertTrue(sam.try_transfer(address(stakeLocker1), address(sid), stakeAmount));

        // Check balances and stake dates are correct
        assertEq(stakeLocker1.balanceOf(address(sam)), 0);
        assertEq(stakeLocker1.balanceOf(address(sid)), stakeAmount * 2);
        assertEq(stakeLocker1.stakeDate(address(sam)), start);         // Stays the same
        assertEq(stakeLocker1.stakeDate(address(sid)), newStakeDate);  // Gets updated
    }

    function setUpLoanAndRepay() public {
        mint("USDC", address(leo), 10_000_000 * USD);  // Mint USDC to LP
        leo.approve(USDC, address(pool1), MAX_UINT);   // LP approves USDC

        leo.deposit(address(pool1), 10_000_000 * USD);                                        // LP deposits 10m USDC to Pool
        pat.fundLoan(address(pool1), address(loan1), address(dlFactory1), 10_000_000 * USD);  // PD funds loan for 10m USDC

        uint256 cReq = loan1.collateralRequiredForDrawdown(10_000_000 * USD);  // WETH required for 100_000_000 USDC drawdown on loan
        mint("WETH", address(bob), cReq);                                      // Mint WETH to borrower
        bob.approve(WETH, address(loan1), MAX_UINT);                           // Borrower approves WETH
        bob.drawdown(address(loan1), 10_000_000 * USD);                        // Borrower draws down 10m USDC

        mint("USDC", address(bob), 10_000_000 * USD);  // Mint USDC to Borrower for repayment plus interest
        bob.approve(USDC, address(loan1), MAX_UINT);   // Borrower approves USDC
        bob.makeFullPayment(address(loan1));           // Borrower makes full payment, which includes interest

        pat.claim(address(pool1), address(loan1), address(dlFactory1));  // PD claims interest, distributing funds to stakeLocker
    }

    function test_unstake(uint256 stakeAmount) public {
        uint256 bptMin = WAD / 10_000_000;
        stakeAmount = constrictToRange(stakeAmount, bptMin, bPool.balanceOf(address(sam)), true);  // 25 WAD max, 1/10m WAD min, or zero (min is roughly equal to 10 cents) (non-zero)

        uint256 stakeDate = block.timestamp;

        makePublicAndStake(stakeAmount);

        assertEq(IERC20(USDC).balanceOf(address(sam)),                          0);
        assertEq(bPool.balanceOf(address(sam)),          (25 * WAD) - stakeAmount);
        assertEq(bPool.balanceOf(address(stakeLocker1)), (50 * WAD) + stakeAmount);  // PD + Staker stake
        assertEq(stakeLocker1.totalSupply(),             (50 * WAD) + stakeAmount);
        assertEq(stakeLocker1.balanceOf(address(sam)),                stakeAmount);
        assertEq(stakeLocker1.stakeDate(address(sam)),                  stakeDate);

        setUpLoanAndRepay();
        assertTrue(!sue.try_intendToUnstake(address(stakeLocker1)));  // Unstake will not work as sue doesn't possess any balance.
        assertTrue( sam.try_intendToUnstake(address(stakeLocker1)));

        hevm.warp(stakeDate + globals.stakerCooldownPeriod() - 1);
        assertTrue(!sam.try_unstake(address(stakeLocker1), stakeAmount));  // Staker cannot unstake BPTs until stakerCooldownPeriod has passed

        hevm.warp(stakeDate + globals.stakerCooldownPeriod());
        assertTrue(!sam.try_unstake(address(stakeLocker1), stakeAmount));  // Still cannot unstake because of lockup period

        hevm.warp(stakeDate + stakeLocker1.lockupPeriod() - globals.stakerCooldownPeriod());  // Warp to first time that account can cooldown and unstake and will be after lockup
        uint256 cooldownTimestamp = block.timestamp;
        assertTrue(sam.try_intendToUnstake(address(stakeLocker1)));

        hevm.warp(cooldownTimestamp + globals.stakerCooldownPeriod() - 1);
        assertTrue(!sam.try_unstake(address(stakeLocker1), stakeAmount));  // Staker cannot unstake BPTs until stakerCooldownPeriod has passed

        hevm.warp(cooldownTimestamp + globals.stakerCooldownPeriod());  // Now account is able to unstake

        uint256 totalStakerEarnings    = IERC20(USDC).balanceOf(address(stakeLocker1));
        uint256 samStakerEarnings_FDT  = stakeLocker1.withdrawableFundsOf(address(sam));
        uint256 samStakerEarnings_calc = totalStakerEarnings * (stakeAmount) / ((50 * WAD) + stakeAmount);  // Staker's portion of staker earnings

        assertTrue(sam.try_unstake(address(stakeLocker1), stakeAmount));  // Staker unstakes all BPTs

        withinPrecision(samStakerEarnings_FDT, samStakerEarnings_calc, 9);

        assertEq(IERC20(USDC).balanceOf(address(sam)),                                samStakerEarnings_FDT);  // Staker got portion of interest
        assertEq(IERC20(USDC).balanceOf(address(stakeLocker1)), totalStakerEarnings - samStakerEarnings_FDT);  // Interest was transferred out of SL

        assertEq(bPool.balanceOf(address(sam)),          25 * WAD);  // Staker's unstaked BPTs
        assertEq(bPool.balanceOf(address(stakeLocker1)), 50 * WAD);  // PD + Staker stake
        assertEq(stakeLocker1.totalSupply(),             50 * WAD);  // Total supply of staked tokens has decreased
        assertEq(stakeLocker1.balanceOf(address(sam)),          0);  // Staker has no staked tokens after unstake
        assertEq(stakeLocker1.stakeDate(address(sam)),  stakeDate);  // StakeDate remains unchanged (doesn't matter since balanceOf == 0 on next stake)
    }

    function test_unstake_paused() public {
        makePublicAndStake(10 * WAD);
        hevm.warp(block.timestamp + stakeLocker1.lockupPeriod());  // Warp to the end of the lockup
        sam.intendToUnstake(address(stakeLocker1));
        hevm.warp(block.timestamp + globals.stakerCooldownPeriod());  // Warp to the end of the unstake cooldown

        // Pause protocol and attempt to unstake()
        assertTrue( emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!sam.try_unstake(address(stakeLocker1), 10 * WAD));
        assertEq(stakeLocker1.balanceOf(address(sam)),     10 * WAD);

        // Unpause protocol and unstake()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(sam.try_unstake(address(stakeLocker1), 10 * WAD));
        assertEq(stakeLocker1.balanceOf(address(sam)),     0 * WAD);
    }

    function test_staker_fdt_accounting(uint256 stakeAmount) public {
        TestObj memory stakeLockerBal;        // StakeLocker total balance of BPTs
        TestObj memory fdtTotalSupply;        // Total Supply of FDTs
        TestObj memory stakerFDTBal;          // Staker FDT balance
        TestObj memory fundsTokenBal;         // FDT accounting of interest earned
        TestObj memory withdrawableFundsOf;   // Interest earned by Staker
        TestObj memory bptLosses;             // FDT accounting of losses from burning
        TestObj memory recognizableLossesOf;  // Recognizable losses of Staker

        uint256 bptMin = WAD / 10_000_000;

        stakeAmount = constrictToRange(stakeAmount,  bptMin, bPool.balanceOf(address(sam)), true);  // 25 WAD max, 1/10m WAD min, or zero (min is roughly equal to 10 cents) (non-zero)

        pat.setAllowlist(address(stakeLocker1), address(sam), true);
        pat.setAllowlist(address(stakeLocker1), address(sid), true);
        pat.setAllowlist(address(stakeLocker1), address(sue), true);

        sam.approve(address(bPool), address(stakeLocker1), MAX_UINT);
        sid.approve(address(bPool), address(stakeLocker1), MAX_UINT);
        sue.approve(address(bPool), address(stakeLocker1), MAX_UINT);

        sam.stake(address(stakeLocker1), stakeAmount);  // Sam stakes before default, unstakes min amount
        sid.stake(address(stakeLocker1), 25 * WAD);     // Sid stakes before default, unstakes full amount

        uint256 interestPaid = setUpLoanMakeOnePaymentAndDefault();  // This does not affect any Pool accounting

        /*****************************************************/
        /*** Make Claim, Update StakeLocker FDT Accounting ***/
        /*****************************************************/

        // Pre-claim FDT and StakeLocker checks (Sam only)
        stakeLockerBal.pre       = bPool.balanceOf(address(stakeLocker1));
        fdtTotalSupply.pre       = stakeLocker1.totalSupply();
        stakerFDTBal.pre         = stakeLocker1.balanceOf(address(sam));
        fundsTokenBal.pre        = IERC20(USDC).balanceOf(address(stakeLocker1));
        withdrawableFundsOf.pre  = stakeLocker1.withdrawableFundsOf(address(sam));
        bptLosses.pre            = stakeLocker1.bptLosses();
        recognizableLossesOf.pre = stakeLocker1.recognizableLossesOf(address(sam));

        assertEq(stakeLockerBal.pre,      stakeAmount + 75 * WAD);  // PD + Sam + Sid stake
        assertEq(fdtTotalSupply.pre,      stakeAmount + 75 * WAD);  // FDT Supply == amount staked
        assertEq(stakerFDTBal.pre,                   stakeAmount);  // Sam FDT balance == amount staked
        assertEq(fundsTokenBal.pre,                            0);  // Claim hasn't been made yet - interest not realized
        assertEq(withdrawableFundsOf.pre,                      0);  // Claim hasn't been made yet - interest not realized
        assertEq(bptLosses.pre,                                0);  // Claim hasn't been made yet - losses   not realized
        assertEq(recognizableLossesOf.pre,                     0);  // Claim hasn't been made yet - losses   not realized

        pat.claim(address(pool1), address(loan1), address(dlFactory1));  // Pool Delegate claims funds, updating accounting for interest and losses from Loan

        // Post-claim FDT and StakeLocker checks (Sam only)
        stakeLockerBal.post       = bPool.balanceOf(address(stakeLocker1));
        fdtTotalSupply.post       = stakeLocker1.totalSupply();
        stakerFDTBal.post         = stakeLocker1.balanceOf(address(sam));
        fundsTokenBal.post        = IERC20(USDC).balanceOf(address(stakeLocker1));
        withdrawableFundsOf.post  = stakeLocker1.withdrawableFundsOf(address(sam));
        bptLosses.post            = stakeLocker1.bptLosses();
        recognizableLossesOf.post = stakeLocker1.recognizableLossesOf(address(sam));

        uint256 stakingRevenue = interestPaid * pool1.stakingFee() / 10_000;  // Portion of interest that goes to the StakeLocker

        assertTrue(stakeLockerBal.post < stakeLockerBal.pre);  // BPTs were burned to cover losses

        assertEq(fdtTotalSupply.post,                                   stakeAmount + 75 * WAD);  // FDT Supply == total amount staked
        assertEq(stakerFDTBal.post,                                                stakeAmount);  // Sam FDT balance == amount staked
        assertEq(fundsTokenBal.post,                                            stakingRevenue);  // Interest claimed
        assertEq(withdrawableFundsOf.post,  stakingRevenue * stakeAmount / fdtTotalSupply.post);  // Sam claim on interest
        assertEq(bptLosses.post,                      stakeLockerBal.pre - stakeLockerBal.post);  // Losses registered in StakeLocker
        assertEq(recognizableLossesOf.post, bptLosses.post * stakeAmount / fdtTotalSupply.post);  // Sam's recognizable losses

        /**************************************************************/
        /*** Staker Post-Loss Minimum Unstake Accounting (Sam Only) ***/
        /**************************************************************/

        // Pre-unstake FDT and StakeLocker checks (update variables)
        stakeLockerBal.pre       = stakeLockerBal.post;
        fdtTotalSupply.pre       = fdtTotalSupply.post;
        stakerFDTBal.pre         = stakerFDTBal.post;
        fundsTokenBal.pre        = fundsTokenBal.post;
        withdrawableFundsOf.pre  = withdrawableFundsOf.post;
        bptLosses.pre            = bptLosses.post;
        recognizableLossesOf.pre = recognizableLossesOf.post;

        assertEq(bPool.balanceOf(address(sam)),        25 * WAD - stakeAmount);  // Starting balance minus staked amount
        assertEq(IERC20(USDC).balanceOf(address(sam)),                      0);  // USDC balance

        assertEq(withdrawableFundsOf.pre,  fundsTokenBal.pre * stakeAmount / fdtTotalSupply.pre);  // Assert FDT interest accounting
        assertEq(recognizableLossesOf.pre,     bptLosses.pre * stakeAmount / fdtTotalSupply.pre);  // Assert FDT loss     accounting

        // re-using the variable to avoid stack too deep issue.
        interestPaid = block.timestamp;

        assertTrue(sam.try_intendToUnstake(address(stakeLocker1)));
        assertEq(stakeLocker1.unstakeCooldown(address(sam)), interestPaid);
        hevm.warp(interestPaid + globals.stakerCooldownPeriod());
        assertTrue(!sam.try_unstake(address(stakeLocker1), recognizableLossesOf.pre - 1));  // Cannot withdraw less than the losses incurred
        hevm.warp(interestPaid + globals.stakerCooldownPeriod() - 1);
        assertTrue(!sam.try_unstake(address(stakeLocker1), recognizableLossesOf.pre));
        hevm.warp(interestPaid + globals.stakerCooldownPeriod());
        assertTrue(sam.try_unstake(address(stakeLocker1), recognizableLossesOf.pre));  // Withdraw lowest possible amount (amt == recognizableLosses), FDTs burned to cover losses, no BPTs left to withdraw

        stakeLockerBal.post       = bPool.balanceOf(address(stakeLocker1));
        fdtTotalSupply.post       = stakeLocker1.totalSupply();
        stakerFDTBal.post         = stakeLocker1.balanceOf(address(sam));
        fundsTokenBal.post        = IERC20(USDC).balanceOf(address(stakeLocker1));
        withdrawableFundsOf.post  = stakeLocker1.withdrawableFundsOf(address(sam));
        bptLosses.post            = stakeLocker1.bptLosses();
        recognizableLossesOf.post = stakeLocker1.recognizableLossesOf(address(sam));

        assertEq(stakeLockerBal.post,                  stakeAmount + 75 * WAD - bptLosses.pre);  // Sam + Sid + Sid stake minus burned BPTs
        assertEq(fdtTotalSupply.post,       stakeAmount + 75 * WAD - recognizableLossesOf.pre);  // FDT Supply == amount staked
        assertEq(stakerFDTBal.post,                    stakeAmount - recognizableLossesOf.pre);  // Sam FDT balance burned on withdraw
        assertEq(fundsTokenBal.post,                 stakingRevenue - withdrawableFundsOf.pre);  // Interest has been claimed
        assertEq(withdrawableFundsOf.post,                                                  0);  // Interest cannot be claimed twice
        assertEq(bptLosses.post,                     bptLosses.pre - recognizableLossesOf.pre);  // Losses accounting has been updated
        assertEq(recognizableLossesOf.post,                                                 0);  // Losses have been recognized

        assertEq(bPool.balanceOf(address(sam)),         25 * WAD - stakeAmount);  // Starting balance minus staked amount (same as before unstake, meaning no BPTs were returned to Sam)
        assertEq(IERC20(USDC).balanceOf(address(sam)), withdrawableFundsOf.pre);  // USDC balance

        /******************************************************/
        /*** Staker Post-Loss Unstake Accounting (Sid Only) ***/
        /******************************************************/

        uint256 initialFundsTokenBal = fundsTokenBal.pre;  // Need this for asserting pre-unstake FDT
        uint256 initialLosses        = bptLosses.pre;      // Need this for asserting pre-unstake FDT

        // Pre-unstake FDT and StakeLocker checks (update variables)
        stakeLockerBal.pre       = stakeLockerBal.post;
        fdtTotalSupply.pre       = fdtTotalSupply.post;
        stakerFDTBal.pre         = stakeLocker1.balanceOf(address(sid));
        fundsTokenBal.pre        = fundsTokenBal.post;
        withdrawableFundsOf.pre  = stakeLocker1.withdrawableFundsOf(address(sid));
        bptLosses.pre            = bptLosses.post;
        recognizableLossesOf.pre = stakeLocker1.recognizableLossesOf(address(sid));

        assertEq(bPool.balanceOf(address(sid)),        0);  // Staked entire balance
        assertEq(IERC20(USDC).balanceOf(address(sid)), 0);  // USDC balance

        assertEq(withdrawableFundsOf.pre,  initialFundsTokenBal * 25 * WAD / (75 * WAD + stakeAmount));  // Assert FDT interest accounting (have to use manual totalSupply because of Sam unstake)
        assertEq(recognizableLossesOf.pre,        initialLosses * 25 * WAD / (75 * WAD + stakeAmount));  // Assert FDT loss     accounting (have to use manual totalSupply because of Sam unstake)

        interestPaid = block.timestamp;

        assertTrue(sid.try_intendToUnstake(address(stakeLocker1)));
        assertEq(stakeLocker1.unstakeCooldown(address(sid)), interestPaid);
        hevm.warp(interestPaid + globals.stakerCooldownPeriod() + 1);
        assertTrue(!sid.try_unstake(address(stakeLocker1), stakerFDTBal.pre + 1));  // Cannot withdraw more than current FDT bal
        assertTrue( sid.try_unstake(address(stakeLocker1), stakerFDTBal.pre));      // Withdraw remaining BPTs

        stakeLockerBal.post       = bPool.balanceOf(address(stakeLocker1));
        fdtTotalSupply.post       = stakeLocker1.totalSupply();
        stakerFDTBal.post         = stakeLocker1.balanceOf(address(sid));
        fundsTokenBal.post        = IERC20(USDC).balanceOf(address(stakeLocker1));
        withdrawableFundsOf.post  = stakeLocker1.withdrawableFundsOf(address(sid));
        bptLosses.post            = stakeLocker1.bptLosses();
        recognizableLossesOf.post = stakeLocker1.recognizableLossesOf(address(sid));

        assertEq(stakeLockerBal.post,      stakeLockerBal.pre - (25 * WAD - recognizableLossesOf.pre));  // Sid's unstake amount minus his losses
        assertEq(fdtTotalSupply.post,                                   fdtTotalSupply.pre - 25 * WAD);  // FDT Supply = previous FDT total supply - unstake amount
        assertEq(stakerFDTBal.post,                                                                 0);  // Sid's entire FDT balance burned on withdraw
        assertEq(fundsTokenBal.post,                      fundsTokenBal.pre - withdrawableFundsOf.pre);  // Interest has been claimed
        assertEq(withdrawableFundsOf.post,                                                          0);  // Interest cannot be claimed twice
        assertEq(bptLosses.post,                             bptLosses.pre - recognizableLossesOf.pre);  // Losses accounting has been updated
        assertEq(recognizableLossesOf.post,                                                         0);  // Losses have been recognized

        assertEq(bPool.balanceOf(address(sid)),        25 * WAD - recognizableLossesOf.pre);  // Starting balance minus losses
        assertEq(IERC20(USDC).balanceOf(address(sid)),             withdrawableFundsOf.pre);  // USDC balance from interest

        /************************************************************/
        /*** Post-Loss Staker Stake/Unstake Accounting (Sue Only) ***/
        /************************************************************/
        // Ensure that Sue has no loss exposure if they stake after a default has already occurred
        uint256 eliStakeAmount = bPool.balanceOf(address(sid));
        sid.transfer(address(bPool), address(sue), eliStakeAmount);  // Sid sends Sue a balance of BPTs so they can stake

        sue.stake(address(stakeLocker1), eliStakeAmount);

        // Pre-unstake FDT and StakeLocker checks (update variables)
        stakeLockerBal.pre       = bPool.balanceOf(address(stakeLocker1));
        fdtTotalSupply.pre       = stakeLocker1.totalSupply();
        stakerFDTBal.pre         = stakeLocker1.balanceOf(address(sue));
        fundsTokenBal.pre        = IERC20(USDC).balanceOf(address(stakeLocker1));
        withdrawableFundsOf.pre  = stakeLocker1.withdrawableFundsOf(address(sue));
        bptLosses.pre            = stakeLocker1.bptLosses();
        recognizableLossesOf.pre = stakeLocker1.recognizableLossesOf(address(sue));

        assertEq(bPool.balanceOf(address(sue)),        0);  // Staked entire balance
        assertEq(IERC20(USDC).balanceOf(address(sue)), 0);  // USDC balance

        assertEq(withdrawableFundsOf.pre,  0);  // Assert FDT interest accounting
        assertEq(recognizableLossesOf.pre, 0);  // Assert FDT loss     accounting

        hevm.warp(block.timestamp + stakeLocker1.lockupPeriod());  // Warp to the end of the lockup

        assertTrue(sue.try_intendToUnstake(address(stakeLocker1)));
        hevm.warp(block.timestamp + globals.stakerCooldownPeriod() + 1);
        sue.unstake(address(stakeLocker1), eliStakeAmount);  // Unstake entire balance

        stakeLockerBal.post       = bPool.balanceOf(address(stakeLocker1));
        fdtTotalSupply.post       = stakeLocker1.totalSupply();
        stakerFDTBal.post         = stakeLocker1.balanceOf(address(sue));
        fundsTokenBal.post        = IERC20(USDC).balanceOf(address(stakeLocker1));
        withdrawableFundsOf.post  = stakeLocker1.withdrawableFundsOf(address(sue));
        bptLosses.post            = stakeLocker1.bptLosses();
        recognizableLossesOf.post = stakeLocker1.recognizableLossesOf(address(sue));

        assertEq(stakeLockerBal.post,      stakeLockerBal.pre - eliStakeAmount);  // Sue recovered full stake
        assertEq(fdtTotalSupply.post,      fdtTotalSupply.pre - eliStakeAmount);  // FDT Supply minus Sue's full stake
        assertEq(stakerFDTBal.post,                                          0);  // Sue FDT balance burned on withdraw
        assertEq(fundsTokenBal.post,                         fundsTokenBal.pre);  // No interest has been claimed
        assertEq(withdrawableFundsOf.post,                                   0);  // Interest cannot be claimed twice
        assertEq(bptLosses.post,                                 bptLosses.pre);  // Losses accounting has not changed
        assertEq(recognizableLossesOf.post,                                  0);  // Losses have been "recognized" (there were none)

        assertEq(bPool.balanceOf(address(sue)),        eliStakeAmount);  // Sue recovered full stake
        assertEq(IERC20(USDC).balanceOf(address(sue)),              0);  // USDC balance from interest (none)
    }

    function test_setAllowlist() public {
        // Pause protocol and attempt setAllowlist()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!pat.try_setAllowlist(address(stakeLocker1), address(sam), true));
        assertTrue(!stakeLocker1.allowed(address(sam)));

        // Unpause protocol and setAllowlist()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(pat.try_setAllowlist(address(stakeLocker1), address(sam), true));
        assertTrue(stakeLocker1.allowed(address(sam)));
    }

}
