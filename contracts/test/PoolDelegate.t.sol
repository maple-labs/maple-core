// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

contract PoolTest is TestUtil {

    using SafeMath for uint256;

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
        newSwapOutRequired = constrictToRange(newSwapOutRequired, 10_000, 1_000_000, true);
        gov.setSwapOutRequired(newSwapOutRequired);

        uint256 minCover; uint256 minCover2; uint256 curCover;
        uint256 minStake; uint256 minStake2; uint256 curStake;
        bool covered;

        /*****************************************/
        /*** Approve Stake Locker To Take BPTs ***/
        /*****************************************/
        pat.approve(address(bPool), pool.stakeLocker(), MAX_UINT);

        uint256 patBptBalance = bPool.balanceOf(address(pat));

        // Pre-state checks.
        assertBalanceState(pool.stakeLocker(), patBptBalance, 0, 0);
        
        (,,, minStake,) = pool.getInitialStakeRequirements();
        // Mint the minStake to PD
        if (minStake > patBptBalance) { 
            transferMoreBpts(address(pat), minStake - patBptBalance);
            patBptBalance = minStake;
        }

        (minCover, curCover, covered, minStake, curStake) = pool.getInitialStakeRequirements();
        {
            (uint256 calc_minStake, uint256 calc_stakerBal) = pool.getPoolSharesRequired(address(bPool), USDC, address(pat), pool.stakeLocker(), minCover);

            assertEq(minCover, globals.swapOutRequired() * USD);                     // Equal to globally specified value
            assertEq(curCover, 0);                                                   // Nothing staked
            assertTrue(!covered);                                                    // Not covered
            assertEq(minStake, calc_minStake);                                       // Mininum stake equals calculated minimum stake     
            assertEq(curStake, calc_stakerBal);                                      // Current stake equals calculated stake
            assertEq(curStake, IERC20(pool.stakeLocker()).balanceOf(address(pat)));  // Current stake equals balance of stakeLocker FDTs
        }

        /***************************************/
        /*** Stake Less than Required Amount ***/
        /***************************************/
        pat.stake(pool.stakeLocker(), minStake - 1);

        // Post-state checks.
        assertBalanceState(pool.stakeLocker(), patBptBalance - (minStake - 1), (minStake - 1), (minStake - 1));

        (minCover2, curCover, covered, minStake2, curStake) = pool.getInitialStakeRequirements();
        {
            (, uint256 calc_stakerBal) = pool.getPoolSharesRequired(address(bPool), USDC, address(pat), pool.stakeLocker(), minCover);

            assertEq(minCover2, minCover);                                           // Doesn't change
            assertTrue(curCover <= minCover);                                        // Not enough cover
            assertTrue(!covered);                                                    // Not covered
            assertEq(minStake2, minStake);                                           // Doesn't change
            assertEq(curStake, calc_stakerBal);                                      // Current stake equals calculated stake
            assertEq(curStake, IERC20(pool.stakeLocker()).balanceOf(address(pat)));  // Current stake equals balance of stakeLocker FDTs
        }

        /***********************************/
        /*** Stake Exact Required Amount ***/
        /***********************************/
        pat.stake(pool.stakeLocker(), 1); // Add one more wei of BPT to get to minStake amount

        // Post-state checks.
        assertBalanceState(pool.stakeLocker(), patBptBalance - minStake, minStake, minStake);

        (minCover2, curCover, covered, minStake2, curStake) = pool.getInitialStakeRequirements();

        (, uint256 calc_stakerBal) = pool.getPoolSharesRequired(address(bPool), USDC, address(pat), pool.stakeLocker(), minCover);

        assertEq(minCover2, minCover);                                           // Doesn't change
        withinPrecision(curCover, minCover, 6);                                  // Roughly enough
        assertTrue(covered);                                                     // Covered
        assertEq(minStake2, minStake);                                           // Doesn't change
        assertEq(curStake, calc_stakerBal);                                      // Current stake equals calculated stake
        assertEq(curStake, IERC20(pool.stakeLocker()).balanceOf(address(pat)));  // Current stake equals balance of stakeLocker FDTs
    }

    function test_stake_and_finalize() public {

        /*****************************************/
        /*** Approve Stake Locker To Take BPTs ***/
        /*****************************************/
        address stakeLocker = pool.stakeLocker();
        pat.approve(address(bPool), stakeLocker, uint256(-1));

        // Pre-state checks.
        assertBalanceState(stakeLocker, 50 * WAD, 0, 0);

        /***************************************/
        /*** Stake Less than Required Amount ***/
        /***************************************/
        (,,, uint256 minStake,) = pool.getInitialStakeRequirements();
        pat.stake(pool.stakeLocker(), minStake - 1);

        // Post-state checks.
        assertBalanceState(stakeLocker, 50 * WAD - (minStake - 1), minStake - 1, minStake - 1);

        assertTrue(!pat.try_finalize(address(pool)));  // Can't finalize

        /***********************************/
        /*** Stake Exact Required Amount ***/
        /***********************************/
        pat.stake(stakeLocker, 1); // Add one more wei of BPT to get to minStake amount

        // Post-state checks.
        assertBalanceState(stakeLocker, 50 * WAD - minStake, minStake, minStake);
        assertEq(uint256(pool.poolState()), 0);  // Initialized

        assertTrue(!pam.try_finalize(address(pool)));  // Can't finalize if not PD

        // Pause protocol and attempt finalize()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!pat.try_finalize(address(pool)));
        
        // Unpause protocol and finalize()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(pat.try_finalize(address(pool)));  // PD that staked can finalize

        assertEq(uint256(pool.poolState()), 1);  // Finalized
    }

    function test_setLockupPeriod() public {
        assertEq(  pool.lockupPeriod(), 180 days);
        assertTrue(!pam.try_setLockupPeriod(address(pool), 15 days));       // Cannot set lockup period if not pool delegate
        assertTrue(!pat.try_setLockupPeriod(address(pool), 180 days + 1));  // Cannot increase lockup period
        assertTrue( pat.try_setLockupPeriod(address(pool), 180 days));      // Can set the same lockup period
        assertTrue( pat.try_setLockupPeriod(address(pool), 180 days - 1));  // Can decrease lockup period
        assertEq(pool.lockupPeriod(), 180 days - 1);
        assertTrue(!pat.try_setLockupPeriod(address(pool), 180 days));      // Cannot increase lockup period

        // Pause protocol and attempt setLockupPeriod()
        assertTrue( emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!pat.try_setLockupPeriod(address(pool), 180 days - 2));
        assertEq(pool.lockupPeriod(), 180 days - 1);

        // Unpause protocol and setLockupPeriod()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(pat.try_setLockupPeriod(address(pool), 180 days - 2));
        assertEq(pool.lockupPeriod(), 180 days - 2);
    }

    function test_fundLoan(uint256 depositAmt, uint256 fundAmt) public {
        address stakeLocker   = pool.stakeLocker();
        address liqLocker     = pool.liquidityLocker();
        address fundingLocker = loan.fundingLocker();

        // Finalize the Pool
        finalizePool(pool, pat, true);

        depositAmt = constrictToRange(depositAmt, loan.requestAmount(), loan.requestAmount() + 1000 * USD, true);
        fundAmt    = constrictToRange(fundAmt, 1 * USD, depositAmt, true); 

        // Mint funds and deposit to Pool.
        mintFundsAndDepositIntoPool(leo, pool, depositAmt, depositAmt);

        gov.setValidLoanFactory(address(loanFactory), false);

        assertTrue(!pat.try_fundLoan(address(pool), address(loan), address(dlFactory), depositAmt)); // LoanFactory not in globals

        gov.setValidLoanFactory(address(loanFactory), true);

        assertEq(usdc.balanceOf(liqLocker),               depositAmt);  // Balance of Liquidity Locker
        assertEq(usdc.balanceOf(address(fundingLocker)),           0);  // Balance of Funding Locker
        
        /*******************/
        /*** Fund a Loan ***/
        /*******************/

        // Pause protocol and attempt fundLoan()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!pat.try_fundLoan(address(pool), address(loan), address(dlFactory), fundAmt));

        // Unpause protocol and fundLoan()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(pat.try_fundLoan(address(pool), address(loan), address(dlFactory), fundAmt), "Fail to fund a loan");  // Fund loan for 20 USDC

        DebtLocker debtLocker = DebtLocker(pool.debtLockers(address(loan), address(dlFactory)));

        assertEq(address(debtLocker.loan()),           address(loan));
        assertEq(debtLocker.pool(),                    address(pool));
        assertEq(address(debtLocker.liquidityAsset()), USDC);

        assertEq(usdc.balanceOf(liqLocker),                    depositAmt - fundAmt);  // Balance of Liquidity Locker
        assertEq(usdc.balanceOf(address(fundingLocker)),                    fundAmt);  // Balance of Funding Locker
        assertEq(IERC20(loan).balanceOf(address(debtLocker)),        toWad(fundAmt));  // LoanFDT balance of DebtLocker
        assertEq(pool.principalOut(),                                       fundAmt);  // Outstanding principal in liqiudity pool 1

        /****************************************/
        /*** Fund same loan with the same DL ***/
        /****************************************/
        uint256 newFundAmt = constrictToRange(fundAmt, 1 * USD, depositAmt - fundAmt, true);
        assertTrue(pat.try_fundLoan(address(pool), address(loan), address(dlFactory), newFundAmt)); // Fund same loan for newFundAmt

        assertEq(dlFactory.owner(address(debtLocker)), address(pool));
        assertTrue(dlFactory.isLocker(address(debtLocker)));

        assertEq(usdc.balanceOf(liqLocker),                    depositAmt - fundAmt - newFundAmt);  // Balance of Liquidity Locker
        assertEq(usdc.balanceOf(address(fundingLocker)),                    fundAmt + newFundAmt);  // Balance of Funding Locker
        assertEq(IERC20(loan).balanceOf(address(debtLocker)),        toWad(fundAmt + newFundAmt));  // LoanFDT balance of DebtLocker
        assertEq(pool.principalOut(),                                       fundAmt + newFundAmt);  // Outstanding principal in liqiudity pool 1

        /*******************************************/
        /*** Fund same loan with a different DL ***/
        /*******************************************/
        uint256 newFundAmt2 = constrictToRange(fundAmt, 1 * USD, depositAmt - fundAmt - newFundAmt, true);
        assertTrue(pat.try_fundLoan(address(pool), address(loan), address(dlFactory2), newFundAmt2)); // Fund loan for 15 USDC

        DebtLocker debtLocker2 = DebtLocker(pool.debtLockers(address(loan),  address(dlFactory2)));

        assertEq(address(debtLocker2.loan()),           address(loan));
        assertEq(debtLocker2.pool(),                    address(pool));
        assertEq(address(debtLocker2.liquidityAsset()), USDC);

        assertEq(dlFactory2.owner(address(debtLocker2)), address(pool));
        assertTrue(dlFactory2.isLocker(address(debtLocker2)));

        assertEq(usdc.balanceOf(liqLocker),                    depositAmt - fundAmt - newFundAmt - newFundAmt2);  // Balance of Liquidity Locker
        assertEq(usdc.balanceOf(address(fundingLocker)),                    fundAmt + newFundAmt + newFundAmt2);  // Balance of Funding Locker
        assertEq(IERC20(loan).balanceOf(address(debtLocker2)),                              toWad(newFundAmt2));  // LoanFDT balance of DebtLocker 2
        assertEq(pool.principalOut(),                                       fundAmt + newFundAmt + newFundAmt2);  // Outstanding principal in liqiudity pool 1
    }

     function test_deactivate() public {

        /*******************************/
        /*** Finalize liquidity pool ***/
        /*******************************/
        
        finalizePool(pool, pat, true);

        address liquidityAsset         = address(pool.liquidityAsset());
        uint256 liquidityAssetDecimals = IERC20Details(liquidityAsset).decimals();

        // Pre-state checks.
        assertTrue(pool.principalOut() <= 100 * 10 ** liquidityAssetDecimals);

        // Pause protocol and attempt deactivate()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!pat.try_deactivate(address(pool)));

        // Unpause protocol and deactivate()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(pat.try_deactivate(address(pool)));

        // Post-state checks.
        assertEq(int(pool.poolState()), 2);

        // Deactivation should block the following functionality:

        // deposit()
        mint("USDC", address(leo), 1_000_000_000 * USD);
        leo.approve(USDC, address(pool), uint256(-1));
        assertTrue(!leo.try_deposit(address(pool), 100_000_000 * USD));

        // fundLoan()
        assertTrue(!pat.try_fundLoan(address(pool), address(loan), address(dlFactory), 1));

        // deactivate()
        assertTrue(!pat.try_deactivate(address(pool)));

    }

    function test_deactivate_fail(uint256 depositAmt, uint256 fundAmt) public {

        /*******************************/
        /*** Finalize liquidity pool ***/
        /*******************************/
        
        finalizePool(pool, pat, true);
        
        /**************************************************/
        /*** Mint and deposit funds into liquidity pool ***/
        /**************************************************/

        depositAmt = constrictToRange(depositAmt, loan.requestAmount(), loan.requestAmount() + 100_000_000 * USD, true);
        fundAmt    = constrictToRange(fundAmt, 101 * USD, depositAmt, true); 

        mintFundsAndDepositIntoPool(leo, pool, loan.requestAmount() + 100_000_000 * USD, depositAmt);

        /************************************/
        /*** Fund loan / loan2 (Excess) ***/
        /************************************/
        
        assertTrue(pat.try_fundLoan(address(pool), address(loan),  address(dlFactory2), fundAmt));

        address liquidityAsset         = address(pool.liquidityAsset());
        uint256 liquidityAssetDecimals = IERC20Details(liquidityAsset).decimals();

        // Pre-state checks.
        assertTrue(pool.principalOut() >= 100 * 10 ** liquidityAssetDecimals);
        assertTrue(!pat.try_deactivate(address(pool)));
    }

    // TODO: Test with losses.
    function test_view_balance(uint256 depositAmt) public {
        /*******************************/
        /*** Finalize liquidity pool ***/
        /*******************************/
        
        finalizePool(pool, pat, true);

        /**************************************************/
        /*** Mint and deposit funds into liquidity pool ***/
        /**************************************************/

        depositAmt = constrictToRange(depositAmt, loan.requestAmount(), loan.requestAmount() + 1_000_000 * USD, true);

        mintFundsAndDepositIntoPool(lee, pool, loan.requestAmount() + 1_000_000 * USD, depositAmt);

        // Fund loan, drawdown, make payment and claim so lee can claim interest
        assertTrue(pat.try_fundLoan(address(pool), address(loan3), address(dlFactory), depositAmt), "Fail to fund the loan");

        drawdown(loan3, bud, depositAmt);
        doFullLoanPayment(loan3, bud); 
        pat.claim(address(pool), address(loan3), address(dlFactory));

        uint256 withdrawDate = pool.depositDate(address(lee)).add(pool.lockupPeriod());

        hevm.warp(withdrawDate - 1);
        (uint256 total_lee, uint256 principal_lee, uint256 interest_lee) = pool.claimableFunds(address(lee));

        // Deposit is still in lock-up
        assertEq(principal_lee, 0);
        assertEq(interest_lee, pool.withdrawableFundsOf(address(lee)));
        assertEq(total_lee, principal_lee + interest_lee);

        hevm.warp(withdrawDate + 1);
        (total_lee, principal_lee, interest_lee) = pool.claimableFunds(address(lee));

        assertEq(principal_lee, pool.balanceOf(address(lee)) * USD / WAD); // (might need to use withinDiff for this)
        assertEq(interest_lee,  pool.withdrawableFundsOf(address(lee)));
        assertEq(total_lee,     principal_lee + interest_lee);

        uint256 lee_bal_pre = IERC20(pool.liquidityAsset()).balanceOf(address(lee));
        
        make_withdrawable(lee, pool);

        assertTrue(lee.try_withdraw(address(pool), principal_lee), "Failed to withdraw claimable_kim");
        
        uint256 lee_bal_post = IERC20(pool.liquidityAsset()).balanceOf(address(lee));

        assertEq(lee_bal_post - lee_bal_pre, principal_lee + interest_lee);
    }

    function test_reclaim_erc20(uint256 mintedUsdc, uint256 mintedDai, uint256 mintedWeth) external {
        // Transfer different assets into the Pool

        mintedUsdc = constrictToRange(mintedUsdc, 500 * USD, 1_000_000 * USD, true);
        mintedDai  = constrictToRange(mintedDai,  500 * WAD, 1_000_000 * WAD, true);
        mintedWeth = constrictToRange(mintedWeth, 500 * WAD, 1_000_000 * WAD, true);

        mint("USDC", address(pool), mintedUsdc);
        mint("DAI",  address(pool), mintedDai);
        mint("WETH", address(pool), mintedWeth);

        Governor fakeGov = new Governor();

        uint256 beforeBalanceDAI  = IERC20(DAI).balanceOf(address(gov));
        uint256 beforeBalanceWETH = IERC20(WETH).balanceOf(address(gov));

        assertTrue(!fakeGov.try_reclaimERC20(address(pool), DAI));
        assertTrue(    !gov.try_reclaimERC20(address(pool), USDC));  // Can't claim the USDC from the Pool as it is liquidityAsset of the Pool.
        assertTrue(    !gov.try_reclaimERC20(address(pool), address(0)));
        assertTrue(     gov.try_reclaimERC20(address(pool), DAI));
        assertTrue(     gov.try_reclaimERC20(address(pool), WETH));

        uint256 afterBalanceDAI  = IERC20(DAI).balanceOf(address(gov));
        uint256 afterBalanceWETH = IERC20(WETH).balanceOf(address(gov));

        assertEq(afterBalanceDAI - beforeBalanceDAI,    mintedDai);
        assertEq(afterBalanceWETH - beforeBalanceWETH,  mintedWeth);
    }

    function test_setAllowList() public {
        // Pause protocol and attempt setAllowList()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!pat.try_setAllowList(address(pool), address(leo), true));
        assertTrue(!pool.allowedLiquidityProviders(address(leo)));

        // Unpause protocol and setAllowList()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(pat.try_setAllowList(address(pool), address(leo), true));
        assertTrue(pool.allowedLiquidityProviders(address(leo)));
    }

    function test_setPoolAdmin() public {
        // Pause protocol and attempt setPoolAdmin()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!pat.try_setPoolAdmin(address(pool), address(securityAdmin), true));
        assertTrue(!pool.poolAdmins(address(securityAdmin)));

        // Unpause protocol and setPoolAdmin()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(pat.try_setPoolAdmin(address(pool), address(securityAdmin), true));
        assertTrue(pool.poolAdmins(address(securityAdmin)));
    }

     function test_setStakingFee() public {
        assertEq(pool.stakingFee(),  500);
        assertEq(pool.delegateFee(), 100);
        assertTrue(!pam.try_setStakingFee(address(pool), 1000));  // Cannot set stakingFee if not pool delegate
        assertTrue(!pat.try_setStakingFee(address(pool), 9901));  // Cannot set stakingFee if sum of fees is over 100%
        assertTrue( pat.try_setStakingFee(address(pool), 9900));  // Can set stakingFee if pool delegate
        assertEq(pool.stakingFee(),                      9900);

        // Pause protocol and attempt setLockupPeriod()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!pat.try_setStakingFee(address(pool), 2000));  // Cannot set stakingFee if protocol is paused
        assertEq(pool.stakingFee(),                      9900);

        // Unpause protocol and setLockupPeriod()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(pat.try_setStakingFee(address(pool), 2000));
        assertEq(pool.stakingFee(),                     2000);
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