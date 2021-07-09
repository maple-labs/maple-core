// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import { TestUtil } from "test/TestUtil.sol";

contract PoolTest is TestUtil {

    function setUp() public {
        setUpGlobals();
        setUpTokens();
        setUpOracles();
        setUpFactories();
        setUpCalcs();
        setUpActors();
        setUpBalancerPool();
        createLiquidityPools();
        createLoans();
    }

    function test_getInitialStakeRequirements(uint256 newSwapOutRequired) public {
        newSwapOutRequired = constrictToRange(newSwapOutRequired, 10_000, 500_000, true);
        gov.setSwapOutRequired(newSwapOutRequired);

        uint256 minCover; uint256 minCover2; uint256 curCover;
        uint256 minStake; uint256 minStake2; uint256 curStake;
        bool covered;

        /*****************************************/
        /*** Approve StakeLocker To Take BPTs ***/
        /*****************************************/
        pat.approve(address(bPool), pool1.stakeLocker(), MAX_UINT);

        uint256 patBptBalance = bPool.balanceOf(address(pat));

        // Pre-state checks.
        assertBalanceState(pool1.stakeLocker(), patBptBalance, 0, 0);

        (,,, minStake,) = pool1.getInitialStakeRequirements();
        // Mint the minStake to PD
        if (minStake > patBptBalance) {
            transferMoreBpts(address(pat), minStake - patBptBalance);
            patBptBalance = minStake;
        }

        (minCover, curCover, covered, minStake, curStake) = pool1.getInitialStakeRequirements();
        {
            (uint256 calc_minStake, uint256 calc_stakerBal) = pool1.getPoolSharesRequired(address(bPool), USDC, address(pat), pool1.stakeLocker(), minCover);

            assertEq(minCover, globals.swapOutRequired() * USD);                      // Equal to globally specified value
            assertEq(curCover, 0);                                                    // Nothing staked
            assertTrue(!covered);                                                     // Not covered
            assertEq(minStake, calc_minStake);                                        // Minimum stake equals calculated minimum stake
            assertEq(curStake, calc_stakerBal);                                       // Current stake equals calculated stake
            assertEq(curStake, IERC20(pool1.stakeLocker()).balanceOf(address(pat)));  // Current stake equals balance of StakeLockerFDTs
        }

        /***************************************/
        /*** Stake Less than Required Amount ***/
        /***************************************/
        pat.stake(pool1.stakeLocker(), minStake - 1);

        // Post-state checks.
        assertBalanceState(pool1.stakeLocker(), patBptBalance - (minStake - 1), (minStake - 1), (minStake - 1));

        (minCover2, curCover, covered, minStake2, curStake) = pool1.getInitialStakeRequirements();
        {
            (, uint256 calc_stakerBal) = pool1.getPoolSharesRequired(address(bPool), USDC, address(pat), pool1.stakeLocker(), minCover);

            assertEq(minCover2, minCover);                                            // Doesn't change
            assertTrue(curCover <= minCover);                                         // Not enough cover
            assertTrue(!covered);                                                     // Not covered
            assertEq(minStake2, minStake);                                            // Doesn't change
            assertEq(curStake, calc_stakerBal);                                       // Current stake equals calculated stake
            assertEq(curStake, IERC20(pool1.stakeLocker()).balanceOf(address(pat)));  // Current stake equals balance of StakeLockerFDTs
        }

        /***********************************/
        /*** Stake Exact Required Amount ***/
        /***********************************/
        pat.stake(pool1.stakeLocker(), 1);  // Add one more wei of BPT to get to minStake amount

        // Post-state checks.
        assertBalanceState(pool1.stakeLocker(), patBptBalance - minStake, minStake, minStake);

        (minCover2, curCover, covered, minStake2, curStake) = pool1.getInitialStakeRequirements();

        (, uint256 calc_stakerBal) = pool1.getPoolSharesRequired(address(bPool), USDC, address(pat), pool1.stakeLocker(), minCover);

        assertEq(minCover2, minCover);                                            // Doesn't change
        withinPrecision(curCover, minCover, 6);                                   // Roughly enough
        assertTrue(covered);                                                      // Covered
        assertEq(minStake2, minStake);                                            // Doesn't change
        assertEq(curStake, calc_stakerBal);                                       // Current stake equals calculated stake
        assertEq(curStake, IERC20(pool1.stakeLocker()).balanceOf(address(pat)));  // Current stake equals balance of StakeLockerFDTs
    }

    function test_stake_and_finalize() public {

        /*****************************************/
        /*** Approve StakeLocker To Take BPTs ***/
        /*****************************************/
        address stakeLocker = pool1.stakeLocker();
        pat.approve(address(bPool), stakeLocker, uint256(-1));

        // Pre-state checks.
        assertBalanceState(stakeLocker, 50 * WAD, 0, 0);

        /***************************************/
        /*** Stake Less than Required Amount ***/
        /***************************************/
        (,,, uint256 minStake,) = pool1.getInitialStakeRequirements();
        pat.stake(pool1.stakeLocker(), minStake - 1);

        // Post-state checks.
        assertBalanceState(stakeLocker, 50 * WAD - (minStake - 1), minStake - 1, minStake - 1);

        assertTrue(!pat.try_finalize(address(pool1)));  // Can't finalize

        /***********************************/
        /*** Stake Exact Required Amount ***/
        /***********************************/
        pat.stake(stakeLocker, 1);  // Add one more wei of BPT to get to minStake amount

        // Post-state checks.
        assertBalanceState(stakeLocker, 50 * WAD - minStake, minStake, minStake);
        assertEq(uint256(pool1.poolState()), 0);  // Initialized

        assertTrue(!pam.try_finalize(address(pool1)));  // Can't finalize if not PD

        // Pause protocol and attempt finalize()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!pat.try_finalize(address(pool1)));

        // Unpause protocol and finalize()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(pat.try_finalize(address(pool1)));  // PD that staked can finalize

        assertEq(uint256(pool1.poolState()), 1);  // Finalized
    }

    function test_setLockupPeriod() public {
        assertEq(pool1.lockupPeriod(), 180 days);
        assertTrue(!pam.try_setLockupPeriod(address(pool1), 15 days));       // Cannot set lockup period if not pool delegate
        assertTrue(!pat.try_setLockupPeriod(address(pool1), 180 days + 1));  // Cannot increase lockup period
        assertTrue( pat.try_setLockupPeriod(address(pool1), 180 days));      // Can set the same lockup period
        assertTrue( pat.try_setLockupPeriod(address(pool1), 180 days - 1));  // Can decrease lockup period
        assertEq(pool1.lockupPeriod(), 180 days - 1);
        assertTrue(!pat.try_setLockupPeriod(address(pool1), 180 days));      // Cannot increase lockup period

        // Pause protocol and attempt setLockupPeriod()
        assertTrue( emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!pat.try_setLockupPeriod(address(pool1), 180 days - 2));
        assertEq(pool1.lockupPeriod(), 180 days - 1);

        // Unpause protocol and setLockupPeriod()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(pat.try_setLockupPeriod(address(pool1), 180 days - 2));
        assertEq(pool1.lockupPeriod(), 180 days - 2);
    }

    function test_fundLoan(uint256 depositAmt, uint256 fundAmt) public {
        address liqLocker     = pool1.liquidityLocker();
        address fundingLocker = loan1.fundingLocker();

        // Finalize the Pool
        finalizePool(pool1, pat, true);

        depositAmt = constrictToRange(depositAmt, loan1.requestAmount(), loan1.requestAmount() + 1000 * USD, true);
        fundAmt    = constrictToRange(fundAmt, 1 * USD, depositAmt, true);

        // Mint funds and deposit to Pool.
        mintFundsAndDepositIntoPool(leo, pool1, depositAmt, depositAmt);

        gov.setValidLoanFactory(address(loanFactory), false);

        assertTrue(!pat.try_fundLoan(address(pool1), address(loan1), address(dlFactory1), depositAmt));  // LoanFactory not in globals

        gov.setValidLoanFactory(address(loanFactory), true);

        assertEq(usdc.balanceOf(liqLocker),               depositAmt);  // Balance of LiquidityLocker
        assertEq(usdc.balanceOf(address(fundingLocker)),           0);  // Balance of FundingLocker

        /*******************/
        /*** Fund a Loan ***/
        /*******************/

        // Pause protocol and attempt fundLoan()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!pat.try_fundLoan(address(pool1), address(loan1), address(dlFactory1), fundAmt));

        // Unpause protocol and fundLoan()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(pat.try_fundLoan(address(pool1), address(loan1), address(dlFactory1), fundAmt), "Fail to fund a loan");  // Fund loan for 20 USDC

        DebtLocker debtLocker = DebtLocker(pool1.debtLockers(address(loan1), address(dlFactory1)));

        assertEq(address(debtLocker.loan()),           address(loan1));
        assertEq(debtLocker.pool(),                    address(pool1));
        assertEq(address(debtLocker.liquidityAsset()), USDC);

        assertEq(usdc.balanceOf(liqLocker),                    depositAmt - fundAmt);  // Balance of LiquidityLocker
        assertEq(usdc.balanceOf(address(fundingLocker)),                    fundAmt);  // Balance of FundingLocker
        assertEq(IERC20(loan1).balanceOf(address(debtLocker)),       toWad(fundAmt));  // LoanFDT balance of DebtLocker
        assertEq(pool1.principalOut(),                                      fundAmt);  // Outstanding principal in liquidity pool 1

        /***************************************/
        /*** Fund same loan with the same DL ***/
        /***************************************/
        uint256 newFundAmt = constrictToRange(fundAmt, 1 * USD, depositAmt - fundAmt, true);
        assertTrue(pat.try_fundLoan(address(pool1), address(loan1), address(dlFactory1), newFundAmt));  // Fund same loan for newFundAmt

        assertEq(dlFactory1.owner(address(debtLocker)), address(pool1));
        assertTrue(dlFactory1.isLocker(address(debtLocker)));

        assertEq(usdc.balanceOf(liqLocker),                    depositAmt - fundAmt - newFundAmt);  // Balance of LiquidityLocker
        assertEq(usdc.balanceOf(address(fundingLocker)),                    fundAmt + newFundAmt);  // Balance of FundingLocker
        assertEq(IERC20(loan1).balanceOf(address(debtLocker)),       toWad(fundAmt + newFundAmt));  // LoanFDT balance of DebtLocker
        assertEq(pool1.principalOut(),                                      fundAmt + newFundAmt);  // Outstanding principal in liquidity pool 1

        /******************************************/
        /*** Fund same loan with a different DL ***/
        /******************************************/
        uint256 newFundAmt2 = constrictToRange(fundAmt, 1 * USD, depositAmt - fundAmt - newFundAmt, true);
        assertTrue(pat.try_fundLoan(address(pool1), address(loan1), address(dlFactory2), newFundAmt2));  // Fund loan for 15 USDC

        DebtLocker debtLocker2 = DebtLocker(pool1.debtLockers(address(loan1), address(dlFactory2)));

        assertEq(address(debtLocker2.loan()),           address(loan1));
        assertEq(debtLocker2.pool(),                    address(pool1));
        assertEq(address(debtLocker2.liquidityAsset()), USDC);

        assertEq(dlFactory2.owner(address(debtLocker2)), address(pool1));
        assertTrue(dlFactory2.isLocker(address(debtLocker2)));

        assertEq(usdc.balanceOf(liqLocker),                    depositAmt - fundAmt - newFundAmt - newFundAmt2);  // Balance of LiquidityLocker
        assertEq(usdc.balanceOf(address(fundingLocker)),                    fundAmt + newFundAmt + newFundAmt2);  // Balance of FundingLocker
        assertEq(IERC20(loan1).balanceOf(address(debtLocker2)),                             toWad(newFundAmt2));  // LoanFDT balance of DebtLocker 2
        assertEq(pool1.principalOut(),                                      fundAmt + newFundAmt + newFundAmt2);  // Outstanding principal in liquidity pool 1
    }

    function test_deactivate() public {

        /*******************************/
        /*** Finalize liquidity pool ***/
        /*******************************/

        finalizePool(pool1, pat, true);

        address liquidityAsset         = address(pool1.liquidityAsset());
        uint256 liquidityAssetDecimals = IERC20Details(liquidityAsset).decimals();

        // Pre-state checks.
        assertTrue(pool1.principalOut() <= 100 * 10 ** liquidityAssetDecimals);

        // Pause protocol and attempt deactivate()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!pat.try_deactivate(address(pool1)));

        // Unpause protocol and deactivate()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(pat.try_deactivate(address(pool1)));

        // Post-state checks.
        assertEq(int(pool1.poolState()), 2);

        // Deactivation should block the following functionality:

        // deposit()
        mint("USDC", address(leo), 1_000_000_000 * USD);
        leo.approve(USDC, address(pool1), uint256(-1));
        assertTrue(!leo.try_deposit(address(pool1), 100_000_000 * USD));

        // fundLoan()
        assertTrue(!pat.try_fundLoan(address(pool1), address(loan1), address(dlFactory1), 1));

        // deactivate()
        assertTrue(!pat.try_deactivate(address(pool1)));

    }

    function test_deactivate_fail(uint256 depositAmt, uint256 fundAmt) public {

        /*******************************/
        /*** Finalize liquidity pool ***/
        /*******************************/

        finalizePool(pool1, pat, true);

        /**************************************************/
        /*** Mint and deposit funds into liquidity pool ***/
        /**************************************************/

        depositAmt = constrictToRange(depositAmt, loan1.requestAmount(), loan1.requestAmount() + 100_000_000 * USD, true);
        fundAmt    = constrictToRange(fundAmt, 101 * USD, depositAmt, true);

        mintFundsAndDepositIntoPool(leo, pool1, loan1.requestAmount() + 100_000_000 * USD, depositAmt);

        /***********************************/
        /*** Fund loan1 / loan2 (Excess) ***/
        /***********************************/

        assertTrue(pat.try_fundLoan(address(pool1), address(loan1), address(dlFactory2), fundAmt));

        address liquidityAsset         = address(pool1.liquidityAsset());
        uint256 liquidityAssetDecimals = IERC20Details(liquidityAsset).decimals();

        // Pre-state checks.
        assertTrue(pool1.principalOut() >= 100 * 10 ** liquidityAssetDecimals);
        assertTrue(!pat.try_deactivate(address(pool1)));
    }

    function test_reclaim_erc20(uint256 mintedUsdc, uint256 mintedDai, uint256 mintedWeth) external {
        // Transfer different assets into the Pool

        mintedUsdc = constrictToRange(mintedUsdc, 500 * USD, 1_000_000 * USD, true);
        mintedDai  = constrictToRange(mintedDai,  500 * WAD, 1_000_000 * WAD, true);
        mintedWeth = constrictToRange(mintedWeth, 500 * WAD, 1_000_000 * WAD, true);

        mint("USDC", address(pool1), mintedUsdc);
        mint("DAI",  address(pool1), mintedDai);
        mint("WETH", address(pool1), mintedWeth);

        Governor fakeGov = new Governor();

        uint256 beforeBalanceDAI  = IERC20(DAI).balanceOf(address(gov));
        uint256 beforeBalanceWETH = IERC20(WETH).balanceOf(address(gov));

        assertTrue(!fakeGov.try_reclaimERC20(address(pool1), DAI));
        assertTrue(    !gov.try_reclaimERC20(address(pool1), USDC));  // Can't claim the USDC from the Pool as it is liquidityAsset of the Pool.
        assertTrue(    !gov.try_reclaimERC20(address(pool1), address(0)));
        assertTrue(     gov.try_reclaimERC20(address(pool1), DAI));
        assertTrue(     gov.try_reclaimERC20(address(pool1), WETH));

        uint256 afterBalanceDAI  = IERC20(DAI).balanceOf(address(gov));
        uint256 afterBalanceWETH = IERC20(WETH).balanceOf(address(gov));

        assertEq(afterBalanceDAI - beforeBalanceDAI,    mintedDai);
        assertEq(afterBalanceWETH - beforeBalanceWETH,  mintedWeth);
    }

    function test_setAllowList() public {
        // Pause protocol and attempt setAllowList()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!pat.try_setAllowList(address(pool1), address(leo), true));
        assertTrue(!pool1.allowedLiquidityProviders(address(leo)));

        // Unpause protocol and setAllowList()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(pat.try_setAllowList(address(pool1), address(leo), true));
        assertTrue(pool1.allowedLiquidityProviders(address(leo)));
    }

    function test_setPoolAdmin() public {
        // Pause protocol and attempt setPoolAdmin()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!pat.try_setPoolAdmin(address(pool1), address(securityAdmin), true));
        assertTrue(!pool1.poolAdmins(address(securityAdmin)));

        // Unpause protocol and setPoolAdmin()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(pat.try_setPoolAdmin(address(pool1), address(securityAdmin), true));
        assertTrue(pool1.poolAdmins(address(securityAdmin)));
    }

    function test_setStakingFee() public {
        assertEq(pool1.stakingFee(),  500);
        assertEq(pool1.delegateFee(), 100);
        assertTrue(!pam.try_setStakingFee(address(pool1), 1000));  // Cannot set stakingFee if not pool delegate
        assertTrue(!pat.try_setStakingFee(address(pool1), 9901));  // Cannot set stakingFee if sum of fees is over 100%
        assertTrue( pat.try_setStakingFee(address(pool1), 9900));  // Can set stakingFee if pool delegate
        assertEq(pool1.stakingFee(),                      9900);

        // Pause protocol and attempt setLockupPeriod()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!pat.try_setStakingFee(address(pool1), 2000));  // Cannot set stakingFee if protocol is paused
        assertEq(pool1.stakingFee(),                      9900);

        // Unpause protocol and setLockupPeriod()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(pat.try_setStakingFee(address(pool1), 2000));
        assertEq(pool1.stakingFee(),                     2000);
    }

    /***************/
    /*** Helpers ***/
    /***************/

    function assertBalanceState(address stakeLocker, uint256 patBptBal, uint256 stakeLockerBptBal, uint256 patStakeAmount) internal {
        assertEq(bPool.balanceOf(address(pat)),                patBptBal);          // Pool delegate BPT balance
        assertEq(bPool.balanceOf(stakeLocker),                 stakeLockerBptBal);  // BPT owned by the stakeLocker
        assertEq(IERC20(stakeLocker).balanceOf(address(pat)),  patStakeAmount);     // Stake amount of Pool delegate in stakeLocker
    }

}
