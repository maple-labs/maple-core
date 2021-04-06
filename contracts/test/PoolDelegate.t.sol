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
    
    function test_getInitialStakeRequirements() public {

        gov.setSwapOutRequired(1_000_000);  // TODO: Update this to realistic launch param

        uint256 minCover; uint256 minCover2; uint256 curCover;
        uint256 minStake; uint256 minStake2; uint256 curStake;
        uint256 calc_minStake; uint256 calc_stakerBal;
        bool covered;

        /*****************************************/
        /*** Approve Stake Locker To Take BPTs ***/
        /*****************************************/
        address stakeLocker = pool.stakeLocker();
        pat.approve(address(bPool), stakeLocker, MAX_UINT);

        // Pre-state checks.
        assertBalanceState(stakeLocker, 50 * WAD, 0, 0);

        (minCover, curCover, covered, minStake, curStake) = pool.getInitialStakeRequirements();

        (calc_minStake, calc_stakerBal) = pool.getPoolSharesRequired(address(bPool), USDC, address(pat), stakeLocker, minCover);

        assertEq(minCover, globals.swapOutRequired() * USD);              // Equal to globally specified value
        assertEq(curCover, 0);                                            // Nothing staked
        assertTrue(!covered);                                             // Not covered
        assertEq(minStake, calc_minStake);                                // Mininum stake equals calculated minimum stake     
        assertEq(curStake, calc_stakerBal);                               // Current stake equals calculated stake
        assertEq(curStake, IERC20(stakeLocker).balanceOf(address(pat)));  // Current stake equals balance of stakeLocker FDTs

        /***************************************/
        /*** Stake Less than Required Amount ***/
        /***************************************/
        pat.stake(stakeLocker, minStake - 1);

        // Post-state checks.
        assertBalanceState(stakeLocker, 50 * WAD - (minStake - 1), (minStake - 1), (minStake - 1));

        (minCover2, curCover, covered, minStake2, curStake) = pool.getInitialStakeRequirements();

        (, calc_stakerBal) = pool.getPoolSharesRequired(address(bPool), USDC, address(pat), stakeLocker, minCover);

        assertEq(minCover2, minCover);                                    // Doesn't change
        assertTrue(curCover < minCover);                                  // Not enough cover
        assertTrue(!covered);                                             // Not covered
        assertEq(minStake2, minStake);                                    // Doesn't change
        assertEq(curStake, calc_stakerBal);                               // Current stake equals calculated stake
        assertEq(curStake, IERC20(stakeLocker).balanceOf(address(pat)));  // Current stake equals balance of stakeLocker FDTs

        /***********************************/
        /*** Stake Exact Required Amount ***/
        /***********************************/
        pat.stake(stakeLocker, 1); // Add one more wei of BPT to get to minStake amount

        // Post-state checks.
        assertBalanceState(stakeLocker, 50 * WAD - minStake, minStake, minStake);

        (minCover2, curCover, covered, minStake2, curStake) = pool.getInitialStakeRequirements();

        (, calc_stakerBal) = pool.getPoolSharesRequired(address(bPool), USDC, address(pat), stakeLocker, minCover);

        assertEq(minCover2, minCover);                                    // Doesn't change
        withinPrecision(curCover, minCover, 6);                           // Roughly enough
        assertTrue(covered);                                              // Covered
        assertEq(minStake2, minStake);                                    // Doesn't change
        assertEq(curStake, calc_stakerBal);                               // Current stake equals calculated stake
        assertEq(curStake, IERC20(stakeLocker).balanceOf(address(pat)));  // Current stake equals balance of stakeLocker FDTs
    }

    function test_stake_and_finalize() public {

        /*****************************************/
        /*** Approve Stake Locker To Take BPTs ***/
        /*****************************************/
        address stakeLocker = pool.stakeLocker();
        pat.approve(address(bPool), stakeLocker, uint(-1));

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

    function test_fundLoan() public {
        address stakeLocker   = pool.stakeLocker();
        address liqLocker     = pool.liquidityLocker();
        address fundingLocker = loan.fundingLocker();

        // Finalize the Pool
        finalizePool(pool, pat);

        // Mint funds and deposit to Pool.
        mintFundsAndDepositIntoPool(leo, pool, 100 * USD, 100 * USD);

        gov.setValidLoanFactory(address(loanFactory), false);

        assertTrue(!pat.try_fundLoan(address(pool), address(loan), address(dlFactory), 100 * USD)); // LoanFactory not in globals

        gov.setValidLoanFactory(address(loanFactory), true);

        assertEq(IERC20(USDC).balanceOf(liqLocker),               100 * USD);  // Balance of Liquidity Locker
        assertEq(IERC20(USDC).balanceOf(address(fundingLocker)),          0);  // Balance of Funding Locker
        
        /*******************/
        /*** Fund a Loan ***/
        /*******************/

        // Pause protocol and attempt fundLoan()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!pat.try_fundLoan(address(pool), address(loan), address(dlFactory), 1 * USD));

        // Unpause protocol and fundLoan()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(pat.try_fundLoan(address(pool), address(loan), address(dlFactory), 20 * USD), "Fail to fund a loan");  // Fund loan for 20 USDC

        DebtLocker debtLocker = DebtLocker(pool.debtLockers(address(loan), address(dlFactory)));

        assertEq(address(debtLocker.loan()),           address(loan));
        assertEq(debtLocker.pool(),                    address(pool));
        assertEq(address(debtLocker.liquidityAsset()), USDC);

        assertEq(IERC20(USDC).balanceOf(liqLocker),              80 * USD);  // Balance of Liquidity Locker
        assertEq(IERC20(USDC).balanceOf(address(fundingLocker)), 20 * USD);  // Balance of Funding Locker
        assertEq(IERC20(loan).balanceOf(address(debtLocker)),    20 * WAD);  // LoanToken balance of LT Locker
        assertEq(pool.principalOut(),                            20 * USD);  // Outstanding principal in liqiudity pool 1

        /****************************************/
        /*** Fund same loan with the same DL ***/
        /****************************************/
        assertTrue(pat.try_fundLoan(address(pool), address(loan), address(dlFactory), 25 * USD)); // Fund same loan for 25 USDC

        assertEq(dlFactory.owner(address(debtLocker)), address(pool));
        assertTrue(dlFactory.isLocker(address(debtLocker)));

        assertEq(IERC20(USDC).balanceOf(liqLocker),              55 * USD);  // Balance of Liquidity Locker
        assertEq(IERC20(USDC).balanceOf(address(fundingLocker)), 45 * USD);  // Balance of Funding Locker
        assertEq(IERC20(loan).balanceOf(address(debtLocker)),    45 * WAD);  // LoanToken balance of LT Locker
        assertEq(pool.principalOut(),                            45 * USD);  // Outstanding principal in liqiudity pool 1

        /*******************************************/
        /*** Fund same loan with a different DL ***/
        /*******************************************/
        assertTrue(pat.try_fundLoan(address(pool), address(loan), address(dlFactory2), 10 * USD)); // Fund loan for 15 USDC

        DebtLocker debtLocker2 = DebtLocker(pool.debtLockers(address(loan),  address(dlFactory2)));

        assertEq(address(debtLocker2.loan()),           address(loan));
        assertEq(debtLocker2.pool(),                    address(pool));
        assertEq(address(debtLocker2.liquidityAsset()), USDC);

        assertEq(dlFactory2.owner(address(debtLocker2)), address(pool));
        assertTrue(dlFactory2.isLocker(address(debtLocker2)));

        assertEq(IERC20(USDC).balanceOf(liqLocker),              45 * USD);  // Balance of Liquidity Locker
        assertEq(IERC20(USDC).balanceOf(address(fundingLocker)), 55 * USD);  // Balance of Funding Locker
        assertEq(IERC20(loan).balanceOf(address(debtLocker2)),   10 * WAD);  // LoanToken balance of LT Locker 2
        assertEq(pool.principalOut(),                            55 * USD);  // Outstanding principal in liqiudity pool 1
    }

    //  function test_deactivate() public {

    //     // setUpWithdraw();

    //     address liquidityAsset = address(pool.liquidityAsset());
    //     uint liquidityAssetDecimals = IERC20Details(liquidityAsset).decimals();

    //     // Pre-state checks.
    //     assertTrue(pool.principalOut() <= 100 * 10 ** liquidityAssetDecimals);

    //     // Pause protocol and attempt deactivate()
    //     assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), true));
    //     assertTrue(!pat.try_deactivate(address(pool)));

    //     // Unpause protocol and deactivate()
    //     assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
    //     assertTrue(pat.try_deactivate(address(pool)));

    //     // Post-state checks.
    //     assertEq(int(pool.poolState()), 2);

    //     // Deactivation should block the following functionality:

    //     // deposit()
    //     mint("USDC", address(leo), 1_000_000_000 * USD);
    //     leo.approve(USDC, address(pool), uint(-1));
    //     assertTrue(!leo.try_deposit(address(pool), 100_000_000 * USD));

    //     // fundLoan()
    //     assertTrue(!pat.try_fundLoan(address(pool), address(loan), address(dlFactory), 1));

    //     // deactivate()
    //     assertTrue(!pat.try_deactivate(address(pool)));

    // }

    function test_deactivate_fail() public {

        /*******************************/
        /*** Finalize liquidity pool ***/
        /*******************************/
        
        finalizePool(pool, pat);
        
        /**************************************************/
        /*** Mint and deposit funds into liquidity pool ***/
        /**************************************************/

        mintFundsAndDepositIntoPool(leo, pool, 1_000_000_000 * USD, 100_000_000 * USD);
        mintFundsAndDepositIntoPool(leo, pool, 1_000_000_000 * USD, 300_000_000 * USD);
        mintFundsAndDepositIntoPool(leo, pool, 1_000_000_000 * USD, 600_000_000 * USD);

        gov.setValidLoanFactory(address(loanFactory), true); // Don't remove, not done in setUp()


        /************************************/
        /*** Fund loan / loan2 (Excess) ***/
        /************************************/
        
        assertTrue(pat.try_fundLoan(address(pool), address(loan),  address(dlFactory),  100_000_000 * USD));
        assertTrue(pat.try_fundLoan(address(pool), address(loan),  address(dlFactory),  100_000_000 * USD));
        assertTrue(pat.try_fundLoan(address(pool), address(loan),  address(dlFactory2), 200_000_000 * USD));
        assertTrue(pat.try_fundLoan(address(pool), address(loan),  address(dlFactory2), 200_000_000 * USD));

        assertTrue(pat.try_fundLoan(address(pool), address(loan2), address(dlFactory),   50_000_000 * USD));
        assertTrue(pat.try_fundLoan(address(pool), address(loan2), address(dlFactory),   50_000_000 * USD));
        assertTrue(pat.try_fundLoan(address(pool), address(loan2), address(dlFactory2), 150_000_000 * USD));
        assertTrue(pat.try_fundLoan(address(pool), address(loan2), address(dlFactory2), 150_000_000 * USD));
        

        address liquidityAsset = address(pool.liquidityAsset());
        uint liquidityAssetDecimals = IERC20Details(liquidityAsset).decimals();

        // Pre-state checks.
        assertTrue(pool.principalOut() >= 100 * 10 ** liquidityAssetDecimals);
        assertTrue(!pat.try_deactivate(address(pool)));
    }

    function test_view_balance() public {
        //setUpWithdraw();

        // Mint and deposit 1000 USDC
        mintFundsAndDepositIntoPool(leo, pool, 1_000_000 * USD, 1_000_000 * USD);

        // Fund loan, drawdown, make payment and claim so lee can claim interest
        assertTrue(pat.try_fundLoan(address(pool), address(loan3),  address(dlFactory), 1_000_000 * USD), "Fail to fund the loan");

        drawdown(loan3, bud, 1_000_000 * USD);
        doPartialLoanPayment(loan3, bud); 
        pat.claim(address(pool), address(loan3), address(dlFactory));

        uint withdrawDate = pool.depositDate(address(lee)).add(pool.lockupPeriod());

        hevm.warp(withdrawDate - 1);
        (uint total_kim, uint principal_kim, uint interest_kim) = pool.claimableFunds(address(lee));

        // Deposit is still in lock-up
        assertEq(principal_kim, 0);
        assertEq(interest_kim, pool.withdrawableFundsOf(address(lee)));
        assertEq(total_kim, principal_kim + interest_kim);

        hevm.warp(withdrawDate);
        (total_kim, principal_kim, interest_kim) = pool.claimableFunds(address(lee));

        assertGt(principal_kim, 0);
        assertGt(interest_kim, 0);
        assertGt(total_kim, 0);
        assertEq(total_kim, principal_kim + interest_kim);

        uint256 kim_bal_pre = IERC20(pool.liquidityAsset()).balanceOf(address(lee));
        
        make_withdrawable(lee, pool);

        assertTrue(lee.try_withdraw(address(pool), principal_kim), "Failed to withdraw claimable_kim");
        
        uint256 kim_bal_post = IERC20(pool.liquidityAsset()).balanceOf(address(lee));

        assertEq(kim_bal_post - kim_bal_pre, principal_kim + interest_kim);
    }

    function test_reclaim_erc20() external {
        // Fund the pool with different kind of asset.
        mint("USDC", address(pool), 1000 * USD);
        mint("DAI",  address(pool), 1000 * WAD);
        mint("WETH", address(pool),  100 * WAD);

        Governor fakeGov = new Governor();

        uint256 beforeBalanceDAI  = IERC20(DAI).balanceOf(address(gov));
        uint256 beforeBalanceWETH = IERC20(WETH).balanceOf(address(gov));

        assertTrue(!fakeGov.try_reclaimERC20(address(pool), DAI));
        assertTrue(    !gov.try_reclaimERC20(address(pool), USDC));
        assertTrue(    !gov.try_reclaimERC20(address(pool), address(0)));
        assertTrue(     gov.try_reclaimERC20(address(pool), DAI));
        assertTrue(     gov.try_reclaimERC20(address(pool), WETH));

        uint256 afterBalanceDAI  = IERC20(DAI).balanceOf(address(gov));
        uint256 afterBalanceWETH = IERC20(WETH).balanceOf(address(gov));

        assertEq(afterBalanceDAI - beforeBalanceDAI,   1000 * WAD);
        assertEq(afterBalanceWETH - beforeBalanceWETH,  100 * WAD);
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

    function test_setAllowlistStakeLocker() public {
        // Pause protocol and attempt setAllowlistStakeLocker()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!pat.try_setAllowlistStakeLocker(address(pool), address(sam), true));
        assertTrue(!IStakeLocker(pool.stakeLocker()).allowed(address(sam)));

        // Unpause protocol and setAllowlistStakeLocker()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(pat.try_setAllowlistStakeLocker(address(pool), address(sam), true));
        assertTrue(IStakeLocker(pool.stakeLocker()).allowed(address(sam)));
    }

    function test_setAdmin() public {
        // Pause protocol and attempt setAdmin()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!pat.try_setAdmin(address(pool), address(securityAdmin), true));
        assertTrue(!pool.admins(address(securityAdmin)));

        // Unpause protocol and setAdmin()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(pat.try_setAdmin(address(pool), address(securityAdmin), true));
        assertTrue(pool.admins(address(securityAdmin)));
    }

     function test_setStakingFee() public {
        assertEq(pool.stakingFee(),  500);
        assertEq(pool.delegateFee(), 100);
        assertTrue(!pam.try_setStakingFee(address(pool), 1000));  // Cannot set stakingFee if not pool delegate
        assertTrue(!pat.try_setStakingFee(address(pool), 9901));  // Cannot set stakingFee if sum of fees is over 100%
        assertTrue( pat.try_setStakingFee(address(pool), 9900));  // Can set the same stakingFee if pool delegate
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

    function assertBalanceState(address stakeLocker, uint256 patBalanceOfBPool, uint256 stakeLockerBlanceOfBPool, uint256 stakeOfPat) internal {
        assertEq(bPool.balanceOf(address(pat)),                patBalanceOfBPool);         // PD staked minStake
        assertEq(bPool.balanceOf(stakeLocker),                 stakeLockerBlanceOfBPool);  // minStake BPTs staked
        assertEq(IERC20(stakeLocker).balanceOf(address(pat)),  stakeOfPat);                // PD has minStake SL tokens
    }
}