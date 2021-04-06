// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

contract Treasury { }

contract StakeLockerTest is TestUtil {

    using SafeMath for uint256;

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

    function getNewStakeDate(address who, uint256 amt) public returns(uint256 newStakeDate) {
        uint256 prevDate = stakeLocker.stakeDate(who);
        if (prevDate == uint256(0)) {
            newStakeDate = block.timestamp;
        } else {
            uint256 dTime = block.timestamp - prevDate;
            newStakeDate  = prevDate + (dTime * amt / (stakeLocker.balanceOf(who) + amt));  // stakeDate + (now - stakeDate) * (amt / (balance + amt))
        }
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

        pat.setAllowlistStakeLocker(address(pool), address(sam), true);
        pat.setAllowlistStakeLocker(address(pool), address(sid), true);
        sam.approve(address(bPool), address(stakeLocker), uint256(-1));
        sid.approve(address(bPool), address(stakeLocker), uint256(-1));

        uint256 startDate = block.timestamp;

        stakeLockerBal.pre   = bPool.balanceOf(address(stakeLocker));
        fdtTotalSupply.pre   = stakeLocker.totalSupply();
        stakerBPTBal.pre     = bPool.balanceOf(address(sam));
        stakerFDTBal.pre     = stakeLocker.balanceOf(address(sam));
        stakerStakeDate.pre  = stakeLocker.stakeDate(address(sam));

        sam.stake(address(stakeLocker), initialStake);

        stakeLockerBal.post  = bPool.balanceOf(address(stakeLocker));
        fdtTotalSupply.post  = stakeLocker.totalSupply();
        stakerBPTBal.post    = bPool.balanceOf(address(sam));
        stakerFDTBal.post    = stakeLocker.balanceOf(address(sam));
        stakerStakeDate.post = stakeLocker.stakeDate(address(sam));

        assertEq(stakeLockerBal.post, stakeLockerBal.pre + initialStake, "stakeLockerBal = previous + initialStake");
        assertEq(fdtTotalSupply.post, fdtTotalSupply.pre + initialStake, "fdtTotalSupply = previous + initialStake");
        assertEq(stakerBPTBal.post, stakerBPTBal.pre - initialStake,     "stakerBPTBal = previous - initialStake");
        assertEq(stakerFDTBal.post, stakerFDTBal.pre + initialStake,     "stakerFDTBal = previous + initialStake");
        assertEq(stakerStakeDate.post, startDate,                        "stakerStakeDate = current block timestamp");

        // Warp into the future and stake again
        hevm.warp(startDate + warpTime);
        uint256 newStakeDate = getNewStakeDate(address(sam), additionalStake);

        stakeLockerBal.pre   = bPool.balanceOf(address(stakeLocker));
        fdtTotalSupply.pre   = stakeLocker.totalSupply();
        stakerBPTBal.pre     = bPool.balanceOf(address(sam));
        stakerFDTBal.pre     = stakeLocker.balanceOf(address(sam));
        stakerStakeDate.pre  = stakeLocker.stakeDate(address(sam));

        sam.stake(address(stakeLocker), additionalStake);

        stakeLockerBal.post  = bPool.balanceOf(address(stakeLocker));
        fdtTotalSupply.post  = stakeLocker.totalSupply();
        stakerBPTBal.post    = bPool.balanceOf(address(sam));
        stakerFDTBal.post    = stakeLocker.balanceOf(address(sam));
        stakerStakeDate.post = stakeLocker.stakeDate(address(sam));

        assertEq(stakeLockerBal.post, stakeLockerBal.pre + additionalStake, "stakeLockerBal = previous + additionalStake");
        assertEq(fdtTotalSupply.post, fdtTotalSupply.pre + additionalStake, "fdtTotalSupply = previous + additionalStake");
        assertEq(stakerBPTBal.post, stakerBPTBal.pre - additionalStake,     "stakerBPTBal = previous - additionalStake");
        assertEq(stakerFDTBal.post, stakerFDTBal.pre + additionalStake,     "stakerFDTBal = previous + additionalStake");
        assertEq(stakerStakeDate.post, newStakeDate,                        "stakerStakeDate = expected newStakeDate");

        // Warp into the future and receive an FDT transfer
        hevm.warp(startDate + warpTime);
        newStakeDate = getNewStakeDate(address(sam), transferStake);

        stakeLockerBal.pre   = bPool.balanceOf(address(stakeLocker));
        fdtTotalSupply.pre   = stakeLocker.totalSupply();
        stakerBPTBal.pre     = bPool.balanceOf(address(sam));
        stakerFDTBal.pre     = stakeLocker.balanceOf(address(sam));
        stakerStakeDate.pre  = stakeLocker.stakeDate(address(sam));

        sid.stake(address(stakeLocker), transferStake);
        sid.transfer(address(stakeLocker), address(sam), transferStake);

        stakeLockerBal.post  = bPool.balanceOf(address(stakeLocker));
        fdtTotalSupply.post  = stakeLocker.totalSupply();
        stakerBPTBal.post    = bPool.balanceOf(address(sam));
        stakerFDTBal.post    = stakeLocker.balanceOf(address(sam));
        stakerStakeDate.post = stakeLocker.stakeDate(address(sam));

        assertEq(stakeLockerBal.post, stakeLockerBal.pre + transferStake, "stakeLockerBal = previous + transferStake");
        assertEq(fdtTotalSupply.post, fdtTotalSupply.pre + transferStake, "fdtTotalSupply = previous + transferStake");
        assertEq(stakerBPTBal.post, stakerBPTBal.pre,                     "stakerBPTBal = previous");
        assertEq(stakerFDTBal.post, stakerFDTBal.pre + transferStake,     "stakerFDTBal = previous + transferStake");
        assertEq(stakerStakeDate.post, newStakeDate,                      "stakerStakeDate = expected newStakeDate");
    }

    function test_stake_paused() public {
        pat.setAllowlistStakeLocker(address(pool), address(sam), true);
        sam.approve(address(bPool), address(stakeLocker), 20 * WAD);

        // Pause StakeLocker and attempt stake()
        assertTrue( pat.try_pause(address(stakeLocker)));
        assertTrue(!sam.try_stake(address(stakeLocker), 10 * WAD));
        assertEq(stakeLocker.balanceOf(address(sam)),   0 * WAD);

        // Unpause StakeLocker and stake()
        assertTrue(pat.try_unpause(address(stakeLocker)));
        assertTrue(sam.try_stake(address(stakeLocker), 10 * WAD));
        assertEq(stakeLocker.balanceOf(address(sam)),  10 * WAD);

        // Pause protocol and attempt to stake()
        assertTrue( emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!sam.try_stake(address(stakeLocker), 10 * WAD));
        assertEq(stakeLocker.balanceOf(address(sam)),   10 * WAD);

        // Unpause protocol and stake()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(sam.try_stake(address(stakeLocker), 10 * WAD));
        assertEq(stakeLocker.balanceOf(address(sam)),  20 * WAD);
    }

    function test_stake() public {
        uint256 startDate = block.timestamp;

        assertTrue(!sam.try_stake(address(stakeLocker),   25 * WAD));  // Hasn't approved BPTs
        sam.approve(address(bPool), address(stakeLocker), 25 * WAD);

        assertTrue(!sam.try_stake(address(stakeLocker),   25 * WAD));  // Isn't yet allowlisted

        pat.setAllowlistStakeLocker(address(pool), address(sam), true);

        assertEq(bPool.balanceOf(address(sam)),         25 * WAD);
        assertEq(bPool.balanceOf(address(stakeLocker)), 50 * WAD);  // PD stake
        assertEq(stakeLocker.totalSupply(),             50 * WAD);
        assertEq(stakeLocker.balanceOf(address(sam)),          0);
        assertEq(stakeLocker.stakeDate(address(sam)),          0);

        assertTrue(sam.try_stake(address(stakeLocker), 25 * WAD));

        assertEq(bPool.balanceOf(address(sam)),                 0);
        assertEq(bPool.balanceOf(address(stakeLocker)),  75 * WAD);  // PD + Staker stake
        assertEq(stakeLocker.totalSupply(),              75 * WAD);
        assertEq(stakeLocker.balanceOf(address(sam)),    25 * WAD);
        assertEq(stakeLocker.stakeDate(address(sam)),   startDate);

        sid.approve(address(bPool), address(stakeLocker), 25 * WAD);

        assertTrue(!sid.try_stake(address(stakeLocker), 25 * WAD)); // Isn't allowlisted

        // Open StakeLocker to public
        assertTrue(!stakeLocker.openToPublic());
        assertTrue(!pam.try_openStakeLockerToPublic(address(stakeLocker)));
        assertTrue( pat.try_openStakeLockerToPublic(address(stakeLocker)));
        assertTrue( stakeLocker.openToPublic());
        assertTrue(!stakeLocker.allowed(address(sid)));  // Dan is not an allowed Staker, but StakeLocker is now open to public

        assertEq(bPool.balanceOf(address(sid)),         25 * WAD);
        assertEq(bPool.balanceOf(address(stakeLocker)), 75 * WAD);  // PD stake
        assertEq(stakeLocker.totalSupply(),             75 * WAD);
        assertEq(stakeLocker.balanceOf(address(sid)),          0);
        assertEq(stakeLocker.stakeDate(address(sid)),          0);

        assertTrue(sid.try_stake(address(stakeLocker), 25 * WAD));

        assertEq(bPool.balanceOf(address(sid)),                 0);
        assertEq(bPool.balanceOf(address(stakeLocker)), 100 * WAD);  // PD + Staker stake
        assertEq(stakeLocker.totalSupply(),             100 * WAD);
        assertEq(stakeLocker.balanceOf(address(sid)),    25 * WAD);
        assertEq(stakeLocker.stakeDate(address(sid)),   startDate);
    }

    function test_withdrawFunds_protocol_paused() public {
        // Add Staker to allowlist
        pat.setAllowlistStakeLocker(address(pool), address(sam), true);

        // Stake tokens
        sam.approve(address(bPool), address(stakeLocker), 25 * WAD);
        assertTrue(sam.try_stake(address(stakeLocker), 25 * WAD));

        // Pause protocol and attempt withdrawFunds()
        assertTrue( emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!sam.try_withdrawFunds(address(stakeLocker)));

        // Unpause protocol and withdrawFunds()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(sam.try_withdrawFunds(address(stakeLocker)));
    }

    function test_unstake_cooldown() public {

        pat.setAllowlistStakeLocker(address(pool), address(sam), true); // Add Staker to allowlist

        sam.approve(address(bPool), address(stakeLocker), 15 * WAD); // Stake tokens
        assertTrue(sam.try_stake(address(stakeLocker), 15 * WAD));

        hevm.warp(block.timestamp + stakeLocker.lockupPeriod());  // Warp to end of lockup for test

        gov.setStakerCooldownPeriod(10 days);

        uint256 amt = 5 * WAD; // 1/3 of stake so unstake can happen thrice

        uint256 start = block.timestamp;

        assertTrue(!sam.try_unstake(address(stakeLocker), amt),    "Should fail to unstake 10 WAD because user has to intendToWithdraw");
        assertTrue( sam.try_intendToUnstake(address(stakeLocker)), "Failed to intend to unstake");
        assertEq(stakeLocker.unstakeCooldown(address(sam)), start);
        assertTrue(!sam.try_unstake(address(stakeLocker), amt),    "Should fail to unstake before cooldown period has passed");

        // Just before cooldown ends
        hevm.warp(start + globals.stakerCooldownPeriod() - 1);
        assertTrue(!sam.try_unstake(address(stakeLocker), amt), "Should fail to unstake before cooldown period has passed");

        // Right when cooldown ends
        hevm.warp(start + globals.stakerCooldownPeriod());
        assertTrue(sam.try_unstake(address(stakeLocker), amt), "Should be able to unstake during unstake window");

        // Still within Staker unstake window
        hevm.warp(start + globals.stakerCooldownPeriod() + 1);
        assertTrue(sam.try_unstake(address(stakeLocker), amt), "Should be able to unstake funds again during cooldown window");

        // Second after Staker unstake window ends
        hevm.warp(start + globals.stakerCooldownPeriod() + globals.stakerUnstakeWindow() + 1);
        assertTrue(!sam.try_unstake(address(stakeLocker), amt), "Should fail to unstake funds because now past unstake window");

        uint256 newStart = block.timestamp;

        // Intend to unstake
        assertTrue(sam.try_intendToUnstake(address(stakeLocker)), "Failed to intend to unstake");

        // After cooldown ends but after unstake window
        hevm.warp(newStart + globals.stakerCooldownPeriod() + globals.stakerUnstakeWindow() + 1);
        assertTrue(!sam.try_unstake(address(stakeLocker), amt), "Should fail to unstake after unstake window has passed");

        // Last second of Staker unstake window
        hevm.warp(newStart + globals.stakerCooldownPeriod() + globals.stakerUnstakeWindow());
        assertTrue(sam.try_unstake(address(stakeLocker), amt), "Should be able to unstake during unstake window");
    }

    function test_stake_transfer_restrictions() public {

        pat.setAllowlistStakeLocker(address(pool), address(sam), true); // Add Staker to allowlist

        // transfer() checks

        sam.approve(address(bPool), address(stakeLocker), 25 * WAD); // Stake tokens
        assertTrue(sam.try_stake(address(stakeLocker), 25 * WAD));

        make_transferrable(sam, stakeLocker);

        // Pause protocol and attempt to transfer FDTs
        assertTrue( emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!sam.try_transfer(address(stakeLocker), address(leo), 1 * WAD));

        // Unpause protocol and transfer FDTs
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(sam.try_transfer(address(stakeLocker), address(leo), 1 * WAD));

        make_transferrable(sam, stakeLocker);
        assertTrue(sam.try_transfer(address(stakeLocker), address(pat), 1 * WAD)); // Yes transfer to pool delegate
    }

    function make_transferrable(Staker staker, IStakeLocker stakeLocker) public {
        uint256 currentTime = block.timestamp;
        assertTrue(staker.try_intendToUnstake(address(stakeLocker)));
        assertEq(      stakeLocker.unstakeCooldown(address(staker)), currentTime, "Incorrect value set");
        hevm.warp(currentTime + globals.stakerCooldownPeriod());
    }

    function test_stake_transfer_recipient_withdrawing() public {
        pat.openStakeLockerToPublic(address(stakeLocker));

        uint256 start = block.timestamp;
        uint256 stakeAmt = 25 * WAD;

        // Stake BPTs into StakeLocker
        sam.approve(address(bPool), address(stakeLocker), stakeAmt);
        sam.stake(address(stakeLocker), stakeAmt);
        sid.approve(address(bPool), address(stakeLocker), stakeAmt);
        sid.stake(address(stakeLocker), stakeAmt);

         // Staker (Dan) initiates unstake
        assertTrue(sid.try_intendToUnstake(address(stakeLocker)));
        assertEq(stakeLocker.unstakeCooldown(address(sid)), start);

        // Staker (Che) fails to transfer to Staker (Dan) who is currently unstaking
        assertTrue(!sam.try_transfer(address(stakeLocker), address(sid), stakeAmt));
        hevm.warp(start + globals.stakerCooldownPeriod() + globals.stakerUnstakeWindow());  // Very end of Staker unstake window
        assertTrue(!sam.try_transfer(address(stakeLocker), address(sid), stakeAmt));

        // Staker (Che) successfully transfers to Staker (Dan) who is now outside unstake window
        hevm.warp(start + globals.stakerCooldownPeriod() + globals.stakerUnstakeWindow() + 1);  // Second after Staker unstake window ends
        assertTrue(sam.try_transfer(address(stakeLocker), address(sid), stakeAmt));

        // Check balances and stake dates are correct
        assertEq(stakeLocker.balanceOf(address(sam)), 0);
        assertEq(stakeLocker.balanceOf(address(sid)), stakeAmt * 2);
        uint256 newStakeDate = start + (block.timestamp - start) * (stakeAmt) / ((stakeAmt) + (stakeAmt));
        assertEq(stakeLocker.stakeDate(address(sam)), start);         // Stays the same
        assertEq(stakeLocker.stakeDate(address(sid)), newStakeDate);  // Gets updated
    }

    function setUpLoanAndRepay() public {
        mint("USDC", address(leo), 10_000_000 * USD);  // Mint USDC to LP
        leo.approve(USDC, address(pool), MAX_UINT);    // LP approves USDC

        leo.deposit(address(pool), 10_000_000 * USD);                                      // LP deposits 10m USDC to Pool
        pat.fundLoan(address(pool), address(loan), address(dlFactory), 10_000_000 * USD);  // PD funds loan for 10m USDC

        uint cReq = loan.collateralRequiredForDrawdown(10_000_000 * USD);  // WETH required for 100_000_000 USDC drawdown on loan
        mint("WETH", address(bob), cReq);                                  // Mint WETH to borrower
        bob.approve(WETH, address(loan), MAX_UINT);                        // Borrower approves WETH
        bob.drawdown(address(loan), 10_000_000 * USD);                     // Borrower draws down 10m USDC

        mint("USDC", address(bob), 10_000_000 * USD);  // Mint USDC to Borrower for repayment plus interest
        bob.approve(USDC, address(loan), MAX_UINT);    // Borrower approves USDC
        bob.makeFullPayment(address(loan));            // Borrower makes full payment, which includes interest

        pat.claim(address(pool), address(loan),  address(dlFactory));  // PD claims interest, distributing funds to stakeLocker
    }

    function test_unstake(uint256 stakeAmount) public {

        uint256 bptMin = WAD / 10_000_000;
        stakeAmount = constrictToRange(stakeAmount, bptMin, bPool.balanceOf(address(sam)), true);  // 25 WAD max, 1/10m WAD min, or zero (min is roughly equal to 10 cents) (non-zero)

        uint256 stakeDate = block.timestamp;

        pat.setAllowlistStakeLocker(address(pool), address(sam), true);
        sam.approve(address(bPool), address(stakeLocker), stakeAmount);
        sam.stake(address(stakeLocker), stakeAmount);

        assertEq(IERC20(USDC).balanceOf(address(sam)),                         0);
        assertEq(bPool.balanceOf(address(sam)),         (25 * WAD) - stakeAmount);
        assertEq(bPool.balanceOf(address(stakeLocker)), (50 * WAD) + stakeAmount);  // PD + Staker stake
        assertEq(stakeLocker.totalSupply(),             (50 * WAD) + stakeAmount);
        assertEq(stakeLocker.balanceOf(address(sam)),                stakeAmount);
        assertEq(stakeLocker.stakeDate(address(sam)),                  stakeDate);

        setUpLoanAndRepay();
        assertTrue(!sue.try_intendToUnstake(address(stakeLocker)));  // Unstake will not work as sue doesn't possess any balance.
        assertTrue( sam.try_intendToUnstake(address(stakeLocker)));

        hevm.warp(stakeDate + globals.stakerCooldownPeriod() - 1);
        assertTrue(!sam.try_unstake(address(stakeLocker), stakeAmount));  // Staker cannot unstake BPTs until stakerCooldownPeriod has passed

        hevm.warp(stakeDate + globals.stakerCooldownPeriod());
        assertTrue(!sam.try_unstake(address(stakeLocker), stakeAmount));  // Still cannot unstake because of lockup period

        hevm.warp(stakeDate + stakeLocker.lockupPeriod() - globals.stakerCooldownPeriod());  // Warp to first time that user can cooldown and unstake and will be after lockup
        uint256 cooldownTimestamp = block.timestamp;
        assertTrue(sam.try_intendToUnstake(address(stakeLocker)));

        hevm.warp(cooldownTimestamp + globals.stakerCooldownPeriod() - 1);
        assertTrue(!sam.try_unstake(address(stakeLocker), stakeAmount));  // Staker cannot unstake BPTs until stakerCooldownPeriod has passed

        hevm.warp(cooldownTimestamp + globals.stakerCooldownPeriod());  // Now user is able to unstake

        uint256 totalStakerEarnings    = IERC20(USDC).balanceOf(address(stakeLocker));
        uint256 samStakerEarnings_FDT  = stakeLocker.withdrawableFundsOf(address(sam));
        uint256 samStakerEarnings_calc = totalStakerEarnings * (stakeAmount) / ((50 * WAD) + stakeAmount);  // Staker's portion of staker earnings

        assertTrue(sam.try_unstake(address(stakeLocker), stakeAmount));  // Staker unstakes all BPTs

        withinPrecision(samStakerEarnings_FDT, samStakerEarnings_calc, 9);

        assertEq(IERC20(USDC).balanceOf(address(sam)),                               samStakerEarnings_FDT);  // Staker got portion of interest
        assertEq(IERC20(USDC).balanceOf(address(stakeLocker)), totalStakerEarnings - samStakerEarnings_FDT);  // Interest was transferred out of SL

        assertEq(bPool.balanceOf(address(sam)),          25 * WAD);  // Staker's unstaked BPTs
        assertEq(bPool.balanceOf(address(stakeLocker)),  50 * WAD);  // PD + Staker stake
        assertEq(stakeLocker.totalSupply(),              50 * WAD);  // Total supply of staked tokens has decreased
        assertEq(stakeLocker.balanceOf(address(sam)),           0);  // Staker has no staked tokens after unstake
        assertEq(stakeLocker.stakeDate(address(sam)),   stakeDate);  // StakeDate remains unchanged (doesn't matter since balanceOf == 0 on next stake)
    }

    function test_unstake_paused() public {
        // Make StakeLocker public and stake tokens
        pat.openStakeLockerToPublic(address(stakeLocker));
        sam.approve(address(bPool), address(stakeLocker), 10 * WAD);
        sam.stake(address(stakeLocker), 10 * WAD);
        hevm.warp(block.timestamp + stakeLocker.lockupPeriod());  // Warp to the end of the lockup
        sam.intendToUnstake(address(stakeLocker));
        hevm.warp(block.timestamp + globals.stakerCooldownPeriod());  // Warp to the end of the unstake cooldown

        // Pause protocol and attempt to unstake()
        assertTrue( emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!sam.try_unstake(address(stakeLocker), 10 * WAD));
        assertEq(stakeLocker.balanceOf(address(sam)),     10 * WAD);

        // Unpause protocol and unstake()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(sam.try_unstake(address(stakeLocker), 10 * WAD));
        assertEq(stakeLocker.balanceOf(address(sam)),     0 * WAD);
    }

    function setUpLoanMakeOnePaymentAndDefault() public returns (uint256 interestPaid) {
        // Fund the pool
        mint("USDC", address(leo), 20_000_000 * USD);
        leo.approve(USDC, address(pool), MAX_UINT);
        leo.deposit(address(pool), 10_000_000 * USD);

        // Fund the loan
        pat.fundLoan(address(pool), address(loan), address(dlFactory), 1_000_000 * USD);
        uint cReq = loan.collateralRequiredForDrawdown(1_000_000 * USD);

        // Drawdown loan
        mint("WETH", address(bob), cReq);
        bob.approve(WETH, address(loan), MAX_UINT);
        bob.approve(USDC, address(loan), MAX_UINT);
        bob.drawdown(address(loan), 1_000_000 * USD);

        uint256 preBal = IERC20(USDC).balanceOf(address(bob));
        bob.makePayment(address(loan));  // Make one payment to register interest for Staker
        interestPaid = preBal.sub(IERC20(USDC).balanceOf(address(bob)));

        // Warp to late payment
        uint256 start = block.timestamp;
        uint256 nextPaymentDue = loan.nextPaymentDue();
        uint256 defaultGracePeriod = globals.defaultGracePeriod();
        hevm.warp(start + nextPaymentDue + defaultGracePeriod + 1);

        // Trigger default
        pat.triggerDefault(address(pool), address(loan), address(dlFactory));
    }

    function test_staker_fdt_accounting(uint256 stakeAmount) public {
        TestObj memory stakeLockerBal;        // StakeLocker total balance of BPTs
        TestObj memory fdtTotalSupply;        // Total Supply of FDTs
        TestObj memory stakerFDTBal;          // Staker FDT balance
        TestObj memory fundsTokenBal;         // FDT accounting of interst earned
        TestObj memory withdrawableFundsOf;   // Interest earned by Staker
        TestObj memory bptLosses;             // FDT accounting of losses from burning
        TestObj memory recognizableLossesOf;  // Recognizable losses of Staker

        uint256 bptMin = WAD / 10_000_000;

        stakeAmount = constrictToRange(stakeAmount,  bptMin, bPool.balanceOf(address(sam)), true);  // 25 WAD max, 1/10m WAD min, or zero (min is roughly equal to 10 cents) (non-zero)

        pat.setAllowlistStakeLocker(address(pool), address(sam), true);
        pat.setAllowlistStakeLocker(address(pool), address(sid), true);
        pat.setAllowlistStakeLocker(address(pool), address(sue), true);

        sam.approve(address(bPool), address(stakeLocker), MAX_UINT);
        sid.approve(address(bPool), address(stakeLocker), MAX_UINT);
        sue.approve(address(bPool), address(stakeLocker), MAX_UINT);

        sam.stake(address(stakeLocker), stakeAmount);  // Che stakes before default, unstakes min amount
        sid.stake(address(stakeLocker), 25 * WAD);     // Dan stakes before default, unstakes full amount

        uint256 interestPaid = setUpLoanMakeOnePaymentAndDefault();  // This does not affect any Pool accounting

        /*****************************************************/
        /*** Make Claim, Update StakeLocker FDT Accounting ***/
        /*****************************************************/

        // Pre-claim FDT and StakeLocker checks (Che only)
        stakeLockerBal.pre       = bPool.balanceOf(address(stakeLocker));
        fdtTotalSupply.pre       = stakeLocker.totalSupply();
        stakerFDTBal.pre         = stakeLocker.balanceOf(address(sam));
        fundsTokenBal.pre        = IERC20(USDC).balanceOf(address(stakeLocker));
        withdrawableFundsOf.pre  = stakeLocker.withdrawableFundsOf(address(sam));
        bptLosses.pre            = stakeLocker.bptLosses();
        recognizableLossesOf.pre = stakeLocker.recognizableLossesOf(address(sam));

        assertEq(stakeLockerBal.pre,      stakeAmount + 75 * WAD);  // Che + Dan + Sid stake
        assertEq(fdtTotalSupply.pre,      stakeAmount + 75 * WAD);  // FDT Supply == amount staked
        assertEq(stakerFDTBal.pre,                   stakeAmount);  // Che FDT balance == amount staked
        assertEq(fundsTokenBal.pre,                            0);  // Claim hasnt been made yet - interest not realized
        assertEq(withdrawableFundsOf.pre,                      0);  // Claim hasnt been made yet - interest not realized
        assertEq(bptLosses.pre,                                0);  // Claim hasnt been made yet - losses   not realized
        assertEq(recognizableLossesOf.pre,                     0);  // Claim hasnt been made yet - losses   not realized

        pat.claim(address(pool), address(loan),  address(dlFactory));  // Pool Delegate claims funds, updating accounting for interest and losses from Loan

        // Post-claim FDT and StakeLocker checks (Che only)
        stakeLockerBal.post       = bPool.balanceOf(address(stakeLocker));
        fdtTotalSupply.post       = stakeLocker.totalSupply();
        stakerFDTBal.post         = stakeLocker.balanceOf(address(sam));
        fundsTokenBal.post        = IERC20(USDC).balanceOf(address(stakeLocker));
        withdrawableFundsOf.post  = stakeLocker.withdrawableFundsOf(address(sam));
        bptLosses.post            = stakeLocker.bptLosses();
        recognizableLossesOf.post = stakeLocker.recognizableLossesOf(address(sam));

        uint256 stakingRevenue = interestPaid * pool.stakingFee() / 10_000;  // Portion of interest that goes to the StakeLocker

        assertTrue(stakeLockerBal.post < stakeLockerBal.pre);  // BPTs were burned to cover losses

        assertEq(fdtTotalSupply.post,                                   stakeAmount + 75 * WAD);  // FDT Supply == total amount staked
        assertEq(stakerFDTBal.post,                                                stakeAmount);  // Che FDT balance == amount staked
        assertEq(fundsTokenBal.post,                                            stakingRevenue);  // Interest claimed
        assertEq(withdrawableFundsOf.post,  stakingRevenue * stakeAmount / fdtTotalSupply.post);  // Che claim on interest
        assertEq(bptLosses.post,                      stakeLockerBal.pre - stakeLockerBal.post);  // Losses registered in StakeLocker
        assertEq(recognizableLossesOf.post, bptLosses.post * stakeAmount / fdtTotalSupply.post);  // Che's recognizable losses

        /**************************************************************/
        /*** Staker Post-Loss Minimum Unstake Accounting (Che Only) ***/
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

        assertTrue(sam.try_intendToUnstake(address(stakeLocker)));
        assertEq(stakeLocker.unstakeCooldown(address(sam)), interestPaid);
        hevm.warp(interestPaid + globals.stakerCooldownPeriod());
        assertTrue(!sam.try_unstake(address(stakeLocker), recognizableLossesOf.pre - 1));  // Cannot withdraw less than the losses incurred
        hevm.warp(interestPaid + globals.stakerCooldownPeriod() - 1);
        assertTrue(!sam.try_unstake(address(stakeLocker), recognizableLossesOf.pre));
        hevm.warp(interestPaid + globals.stakerCooldownPeriod());
        assertTrue(sam.try_unstake(address(stakeLocker), recognizableLossesOf.pre));  // Withdraw lowest possible amount (amt == recognizableLosses), FDTs burned to cover losses, no BPTs left to withdraw

        stakeLockerBal.post       = bPool.balanceOf(address(stakeLocker));
        fdtTotalSupply.post       = stakeLocker.totalSupply();
        stakerFDTBal.post         = stakeLocker.balanceOf(address(sam));
        fundsTokenBal.post        = IERC20(USDC).balanceOf(address(stakeLocker));
        withdrawableFundsOf.post  = stakeLocker.withdrawableFundsOf(address(sam));
        bptLosses.post            = stakeLocker.bptLosses();
        recognizableLossesOf.post = stakeLocker.recognizableLossesOf(address(sam));

        assertEq(stakeLockerBal.post,                  stakeAmount + 75 * WAD - bptLosses.pre);  // Che + Dan + Sid stake minus burned BPTs
        assertEq(fdtTotalSupply.post,       stakeAmount + 75 * WAD - recognizableLossesOf.pre);  // FDT Supply == amount staked
        assertEq(stakerFDTBal.post,                    stakeAmount - recognizableLossesOf.pre);  // Che FDT balance burned on withdraw
        assertEq(fundsTokenBal.post,                 stakingRevenue - withdrawableFundsOf.pre);  // Interest has been claimed
        assertEq(withdrawableFundsOf.post,                                                  0);  // Interest cannot be claimed twice
        assertEq(bptLosses.post,                     bptLosses.pre - recognizableLossesOf.pre);  // Losses accounting has been updated
        assertEq(recognizableLossesOf.post,                                                 0);  // Losses have been recognized

        assertEq(bPool.balanceOf(address(sam)),         25 * WAD - stakeAmount);  // Starting balance minus staked amount (same as before unstake, meaning no BPTs were returned to Che)
        assertEq(IERC20(USDC).balanceOf(address(sam)), withdrawableFundsOf.pre);  // USDC balance

        /******************************************************/
        /*** Staker Post-Loss Unstake Accounting (Dan Only) ***/
        /******************************************************/

        uint256 initialFundsTokenBal = fundsTokenBal.pre;  // Need this for asserting pre-unstake FDT
        uint256 initialLosses        = bptLosses.pre;      // Need this for asserting pre-unstake FDT

        // Pre-unstake FDT and StakeLocker checks (update variables)
        stakeLockerBal.pre       = stakeLockerBal.post;
        fdtTotalSupply.pre       = fdtTotalSupply.post;
        stakerFDTBal.pre         = stakeLocker.balanceOf(address(sid));
        fundsTokenBal.pre        = fundsTokenBal.post;
        withdrawableFundsOf.pre  = stakeLocker.withdrawableFundsOf(address(sid));
        bptLosses.pre            = bptLosses.post;
        recognizableLossesOf.pre = stakeLocker.recognizableLossesOf(address(sid));

        assertEq(bPool.balanceOf(address(sid)),        0);  // Staked entire balance
        assertEq(IERC20(USDC).balanceOf(address(sid)), 0);  // USDC balance

        assertEq(withdrawableFundsOf.pre,  initialFundsTokenBal * 25 * WAD / (75 * WAD + stakeAmount));  // Assert FDT interest accounting (have to use manual totalSupply because of Che unstake)
        assertEq(recognizableLossesOf.pre,        initialLosses * 25 * WAD / (75 * WAD + stakeAmount));  // Assert FDT loss     accounting (have to use manual totalSupply because of Che unstake)

        interestPaid = block.timestamp;

        assertTrue(sid.try_intendToUnstake(address(stakeLocker)));
        assertEq(stakeLocker.unstakeCooldown(address(sid)), interestPaid);
        hevm.warp(interestPaid + globals.stakerCooldownPeriod() + 1);
        assertTrue(!sid.try_unstake(address(stakeLocker), stakerFDTBal.pre + 1));  // Cannot withdraw more than current FDT bal
        assertTrue( sid.try_unstake(address(stakeLocker), stakerFDTBal.pre));      // Withdraw remaining BPTs

        stakeLockerBal.post       = bPool.balanceOf(address(stakeLocker));
        fdtTotalSupply.post       = stakeLocker.totalSupply();
        stakerFDTBal.post         = stakeLocker.balanceOf(address(sid));
        fundsTokenBal.post        = IERC20(USDC).balanceOf(address(stakeLocker));
        withdrawableFundsOf.post  = stakeLocker.withdrawableFundsOf(address(sid));
        bptLosses.post            = stakeLocker.bptLosses();
        recognizableLossesOf.post = stakeLocker.recognizableLossesOf(address(sid));

        assertEq(stakeLockerBal.post,      stakeLockerBal.pre - (25 * WAD - recognizableLossesOf.pre));  // Dan's unstake amount minus his losses
        assertEq(fdtTotalSupply.post,                                   fdtTotalSupply.pre - 25 * WAD);  // FDT Supply = previous FDT total supply - unstake amount
        assertEq(stakerFDTBal.post,                                                                 0);  // Dan's entire FDT balance burned on withdraw
        assertEq(fundsTokenBal.post,                      fundsTokenBal.pre - withdrawableFundsOf.pre);  // Interest has been claimed
        assertEq(withdrawableFundsOf.post,                                                          0);  // Interest cannot be claimed twice
        assertEq(bptLosses.post,                             bptLosses.pre - recognizableLossesOf.pre);  // Losses accounting has been updated
        assertEq(recognizableLossesOf.post,                                                         0);  // Losses have been recognized

        assertEq(bPool.balanceOf(address(sid)),        25 * WAD - recognizableLossesOf.pre);  // Starting balance minus losses
        assertEq(IERC20(USDC).balanceOf(address(sid)),             withdrawableFundsOf.pre);  // USDC balance from interest

        /************************************************************/
        /*** Post-Loss Staker Stake/Unstake Accounting (Eli Only) ***/
        /************************************************************/
        // Ensure that Eli has no loss exposure if he stakes after a default has already occured
        uint256 eliStakeAmount = bPool.balanceOf(address(sid));
        sid.transfer(address(bPool), address(sue), eliStakeAmount);  // Dan sends Eli a balance of BPTs so he can stake

        sue.stake(address(stakeLocker), eliStakeAmount);

        // Pre-unstake FDT and StakeLocker checks (update variables)
        stakeLockerBal.pre       = bPool.balanceOf(address(stakeLocker));
        fdtTotalSupply.pre       = stakeLocker.totalSupply();
        stakerFDTBal.pre         = stakeLocker.balanceOf(address(sue));
        fundsTokenBal.pre        = IERC20(USDC).balanceOf(address(stakeLocker));
        withdrawableFundsOf.pre  = stakeLocker.withdrawableFundsOf(address(sue));
        bptLosses.pre            = stakeLocker.bptLosses();
        recognizableLossesOf.pre = stakeLocker.recognizableLossesOf(address(sue));

        assertEq(bPool.balanceOf(address(sue)),        0);  // Staked entire balance
        assertEq(IERC20(USDC).balanceOf(address(sue)), 0);  // USDC balance

        assertEq(withdrawableFundsOf.pre,  0);  // Assert FDT interest accounting
        assertEq(recognizableLossesOf.pre, 0);  // Assert FDT loss     accounting

        hevm.warp(block.timestamp + stakeLocker.lockupPeriod());  // Warp to the end of the lockup

        assertTrue(sue.try_intendToUnstake(address(stakeLocker)));
        hevm.warp(block.timestamp + globals.stakerCooldownPeriod() + 1);
        sue.unstake(address(stakeLocker), eliStakeAmount);  // Unstake entire balance

        stakeLockerBal.post       = bPool.balanceOf(address(stakeLocker));
        fdtTotalSupply.post       = stakeLocker.totalSupply();
        stakerFDTBal.post         = stakeLocker.balanceOf(address(sue));
        fundsTokenBal.post        = IERC20(USDC).balanceOf(address(stakeLocker));
        withdrawableFundsOf.post  = stakeLocker.withdrawableFundsOf(address(sue));
        bptLosses.post            = stakeLocker.bptLosses();
        recognizableLossesOf.post = stakeLocker.recognizableLossesOf(address(sue));

        assertEq(stakeLockerBal.post,      stakeLockerBal.pre - eliStakeAmount);  // Eli recovered full stake
        assertEq(fdtTotalSupply.post,      fdtTotalSupply.pre - eliStakeAmount);  // FDT Supply minus Eli's full stake
        assertEq(stakerFDTBal.post,                                          0);  // Eli FDT balance burned on withdraw
        assertEq(fundsTokenBal.post,                         fundsTokenBal.pre);  // No interest has been claimed
        assertEq(withdrawableFundsOf.post,                                   0);  // Interest cannot be claimed twice
        assertEq(bptLosses.post,                                 bptLosses.pre);  // Losses accounting has not changed
        assertEq(recognizableLossesOf.post,                                  0);  // Losses have been "recognized" (there were none)

        assertEq(bPool.balanceOf(address(sue)),        eliStakeAmount);  // Eli recovered full stake
        assertEq(IERC20(USDC).balanceOf(address(sue)),              0);  // USDC balance from interest (none)
    }
}
