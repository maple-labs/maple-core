// SPDX-License-Identifier: AGPL-3.0-or-later
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

    function test_claim_permissions() public {
        // Set valid loan factory
        gov.setValidLoanFactory(address(loanFactory), true);
        // Finalizing the Pool
        pat.approve(address(bPool), pool.stakeLocker(), uint(-1));
        pat.stake(pool.stakeLocker(), bPool.balanceOf(address(pat)) / 2);

        pat.finalize(address(pool));

        // Add liquidity into the pool (Dan is an LP, but still won't be able to claim)
        mint("USDC", address(lex), 10_000 * USD);
        lex.approve(USDC, address(pool), 10_000 * USD);
        pat.setOpenToPublic(address(pool), true);
        assertTrue(lex.try_deposit(address(pool), 10_000 * USD));

        // Fund Loan (so that debtLocker is instantiated and given LoanFDTs)
        assertTrue(pat.try_fundLoan(address(pool), address(loan), address(dlFactory), 10_000 * USD));
        
        // Assert that LPs and non-admins cannot claim
        assertTrue(!lex.try_claim(address(pool), address(loan), address(dlFactory)));            // Does not have permission to call `claim()` function
        assertTrue(!securityAdmin.try_claim(address(pool), address(loan), address(dlFactory)));  // Does not have permission to call `claim()` function

        // Pool delegate can claim
        assertTrue(pat.try_claim(address(pool), address(loan), address(dlFactory)));   // Successfully call the `claim()` function
        
        // Admin can claim once added
        pat.setAdmin(address(pool), address(securityAdmin), true);                                // Add admin to allow to call the `claim()` function
        assertTrue(securityAdmin.try_claim(address(pool), address(loan), address(dlFactory)));   // Successfully call the `claim()` function

        // Pause protocol and attempt claim()
        assertTrue( emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!securityAdmin.try_claim(address(pool), address(loan), address(dlFactory)));
        
        // Unpause protocol and claim()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(securityAdmin.try_claim(address(pool), address(loan), address(dlFactory)));

        // Admin can't claim after removed
        pat.setAdmin(address(pool), address(securityAdmin), false);                                // Add admin to allow to call the `claim()` function
        assertTrue(!securityAdmin.try_claim(address(pool), address(loan), address(dlFactory)));   // Does not have permission to call `claim()` function
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
        assertEq(bPool.balanceOf(address(pat)),                 50 * WAD);  // PD has 50 BPTs
        assertEq(bPool.balanceOf(stakeLocker),                         0);  // Nothing staked
        assertEq(IERC20(stakeLocker).balanceOf(address(pat)),          0);  // Nothing staked

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
        assertEq(bPool.balanceOf(address(pat)),                50 * WAD - (minStake - 1));  // PD staked minStake - 1 BPTs
        assertEq(bPool.balanceOf(stakeLocker),                             minStake - 1);   // minStake - 1 BPTs staked
        assertEq(IERC20(stakeLocker).balanceOf(address(pat)),              minStake - 1);   // PD has minStake - 1 SL tokens

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
        assertEq(bPool.balanceOf(address(pat)),                50 * WAD - minStake);  // PD staked minStake
        assertEq(bPool.balanceOf(stakeLocker),                            minStake);  // minStake BPTs staked
        assertEq(IERC20(stakeLocker).balanceOf(address(pat)),             minStake);  // PD has minStake SL tokens

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
        assertEq(bPool.balanceOf(address(pat)),                 50 * WAD);  // PD has 50 BPTs
        assertEq(bPool.balanceOf(stakeLocker),                         0);  // Nothing staked
        assertEq(IERC20(stakeLocker).balanceOf(address(pat)),          0);  // Nothing staked

        /***************************************/
        /*** Stake Less than Required Amount ***/
        /***************************************/
        (,,, uint256 minStake,) = pool.getInitialStakeRequirements();
        pat.stake(pool.stakeLocker(), minStake - 1);

        // Post-state checks.
        assertEq(bPool.balanceOf(address(pat)),                50 * WAD - (minStake - 1));  // PD staked minStake - 1 BPTs
        assertEq(bPool.balanceOf(stakeLocker),                             minStake - 1);   // minStake - 1 BPTs staked
        assertEq(IERC20(stakeLocker).balanceOf(address(pat)),              minStake - 1);   // PD has minStake - 1 SL tokens

        assertTrue(!pat.try_finalize(address(pool)));  // Can't finalize

        /***********************************/
        /*** Stake Exact Required Amount ***/
        /***********************************/
        pat.stake(stakeLocker, 1); // Add one more wei of BPT to get to minStake amount

        // Post-state checks.
        assertEq(bPool.balanceOf(address(pat)),                50 * WAD - minStake);  // PD staked minStake
        assertEq(bPool.balanceOf(stakeLocker),                            minStake);  // minStake BPTs staked
        assertEq(IERC20(stakeLocker).balanceOf(address(pat)),             minStake);  // PD has minStake SL tokens
        assertEq(uint256(pool.poolState()), 0);  // Initialized

        assertTrue(!pam.try_finalize(address(pool)));  // Can't finalize if not PD

        // Pause protocol and attempt finalize()
        assertTrue( emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!pat.try_finalize(address(pool)));
        
        // Unpause protocol and finalize()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(pat.try_finalize(address(pool)));  // PD that staked can finalize

        assertEq(uint256(pool.poolState()), 1);  // Finalized
    }

    function test_deposit() public {
        address stakeLocker = pool.stakeLocker();
        address liqLocker   = pool.liquidityLocker();

        pat.approve(address(bPool), stakeLocker, MAX_UINT);
        pat.stake(pool.stakeLocker(), bPool.balanceOf(address(pat)) / 2);

        // Mint 100 USDC into this LP account
        mint("USDC", address(leo), 100 * USD);

        assertTrue(!leo.try_deposit(address(pool), 100 * USD)); // Not finalized

        pat.finalize(address(pool));

        assertTrue(!pool.openToPublic());
        assertTrue(!pool.allowedLiquidityProviders(address(leo)));
        assertTrue(  !leo.try_deposit(address(pool), 100 * USD)); // Not in the LP allow list neither the pool is open to public.

        assertTrue( !pam.try_setAllowList(address(pool), address(leo), true)); // It will fail as `pam` is not the right PD.
        assertTrue(  pat.try_setAllowList(address(pool), address(leo), true));
        assertTrue(pool.allowedLiquidityProviders(address(leo)));
        
        assertTrue(!leo.try_deposit(address(pool), 100 * USD)); // Not Approved

        leo.approve(USDC, address(pool), MAX_UINT);

        assertEq(IERC20(USDC).balanceOf(address(leo)), 100 * USD);
        assertEq(IERC20(USDC).balanceOf(liqLocker),            0);
        assertEq(pool.balanceOf(address(leo)),                0);

        assertTrue(leo.try_deposit(address(pool),    100 * USD));

        assertEq(IERC20(USDC).balanceOf(address(leo)),         0);
        assertEq(IERC20(USDC).balanceOf(liqLocker),    100 * USD);
        assertEq(pool.balanceOf(address(leo)),        100 * WAD);

        // Remove leo from the allowed list
        assertTrue(pat.try_setAllowList(address(pool), address(leo), false));
        mint("USDC", address(leo), 100 * USD);
        assertTrue(!leo.try_deposit(address(pool),    100 * USD));

        mint("USDC", address(lex), 200 * USD);
        lex.approve(USDC, address(pool), MAX_UINT);
        
        assertEq(IERC20(USDC).balanceOf(address(lex)), 200 * USD);
        assertEq(IERC20(USDC).balanceOf(liqLocker),    100 * USD);
        assertEq(pool.balanceOf(address(lex)),                0);

        assertTrue(!pool.allowedLiquidityProviders(address(lex)));
        assertTrue(  !lex.try_deposit(address(pool),  100 * USD)); // Fail to invest as lex is not in the allowed list.

        // Pause protocol and attempt openPoolToPublic()
        assertTrue( emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!pat.try_setOpenToPublic(address(pool), true));

        // Unpause protocol and openPoolToPublic()
        assertTrue( emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(!pam.try_setOpenToPublic(address(pool), true));  // Incorrect PD.
        assertTrue( pat.try_setOpenToPublic(address(pool), true));

        assertTrue(lex.try_deposit(address(pool),     100 * USD));

        assertEq(IERC20(USDC).balanceOf(address(lex)), 100 * USD);
        assertEq(IERC20(USDC).balanceOf(liqLocker),    200 * USD);
        assertEq(pool.balanceOf(address(lex)),        100 * WAD);

        mint("USDC", address(leo), 200 * USD);

        // Pool-specific pause by Pool Delegate via setLiquidityCap(0)
        assertEq( pool.liquidityCap(), MAX_UINT);
        assertTrue(!cam.try_setLiquidityCap(address(pool), 0));
        assertTrue( pat.try_setLiquidityCap(address(pool), 0));
        assertEq( pool.liquidityCap(), 0);
        assertTrue(!leo.try_deposit(address(pool), 1 * USD));
        assertTrue( pat.try_setLiquidityCap(address(pool), MAX_UINT));
        assertEq( pool.liquidityCap(), MAX_UINT);
        assertTrue( leo.try_deposit(address(pool), 100 * USD));
        assertEq( pool.balanceOf(address(leo)), 200 * WAD);
 
        // Protocol-wide pause by Emergency Admin
        assertTrue( emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!leo.try_deposit(address(pool), 1 * USD));
        assertTrue( emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue( leo.try_deposit(address(pool),100 * USD));
        assertEq( pool.balanceOf(address(leo)), 300 * WAD);

        // Pause protocol and attempt setLiquidityCap()
        assertTrue( emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!pat.try_setLiquidityCap(address(pool), MAX_UINT));

        // Unpause protocol and setLiquidityCap()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(pat.try_setLiquidityCap(address(pool), MAX_UINT));

        assertTrue(pat.try_setOpenToPublic(address(pool), false));  // Close pool to public
        assertTrue(!lex.try_deposit(address(pool),    100 * USD));  // Fail to deposit as pool no longer public
    }

    function test_setLockupPeriod() public {
        assertEq(pool.lockupPeriod(), 180 days);
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

    function test_deposit_with_liquidity_cap() public {
    
        address stakeLocker = pool.stakeLocker();

        pat.approve(address(bPool), stakeLocker, MAX_UINT);
        pat.stake(pool.stakeLocker(), bPool.balanceOf(address(pat)) / 2);

        // Mint 1000 USDC into this LP account
        mint("USDC", address(leo), 10_000 * USD);

        pat.finalize(address(pool));
        pat.setOpenToPublic(address(pool), true);

        leo.approve(USDC, address(pool), MAX_UINT);

        // Changes the `liquidityCap`.
        assertTrue(pat.try_setLiquidityCap(address(pool), 900 * USD), "Failed to set liquidity cap");
        assertEq(pool.liquidityCap(), 900 * USD, "Incorrect value set for liquidity cap");

        // Not able to deposit as cap is lower than the deposit amount.
        assertTrue(!pool.isDepositAllowed(1000 * USD), "Deposit should not be allowed because 900 USD < 1000 USD");
        assertTrue(!leo.try_deposit(address(pool), 1000 * USD), "Should not able to deposit 1000 USD");

        // Tries with lower amount it will pass.
        assertTrue(pool.isDepositAllowed(500 * USD), "Deposit should be allowed because 900 USD > 500 USD");
        assertTrue(leo.try_deposit(address(pool), 500 * USD), "Fail to deposit 500 USD");

        // Bob tried again with 600 USDC it fails again.
        assertTrue(!pool.isDepositAllowed(600 * USD), "Deposit should not be allowed because 900 USD < 500 + 600 USD");
        assertTrue(!leo.try_deposit(address(pool), 600 * USD), "Should not able to deposit 600 USD");

        // Set liquidityCap to zero and withdraw
        assertTrue(pat.try_setLiquidityCap(address(pool), 0),  "Failed to set liquidity cap");
        assertTrue(pat.try_setLockupPeriod(address(pool), 0),  "Failed to set the lockup period");
        assertEq(pool.lockupPeriod(), uint256(0),              "Failed to update the lockup period");

        assertTrue(leo.try_intendToWithdraw(address(pool)), "Failed to intend to withdraw");
        
        (uint claimable,,) = pool.claimableFunds(address(leo));

        hevm.warp(block.timestamp + globals.lpCooldownPeriod() + 1);
        assertTrue(leo.try_withdraw(address(pool), claimable),  "Should pass to withdraw the funds from the pool");
    }

    function make_withdrawable(LP investor, Pool pool) public {
        uint256 currentTime = block.timestamp;
        assertTrue(investor.try_intendToWithdraw(address(pool)));
        assertEq(      pool.withdrawCooldown(address(investor)), currentTime, "Incorrect value set");
        hevm.warp(currentTime + globals.lpCooldownPeriod());
    }

    function test_deposit_depositDate() public {
        address stakeLocker = pool.stakeLocker();

        pat.approve(address(bPool), stakeLocker, MAX_UINT);
        pat.stake(pool.stakeLocker(), bPool.balanceOf(address(pat)) / 2);
        pat.setOpenToPublic(address(pool), true);
        
        // Mint 100 USDC into this LP account
        mint("USDC", address(leo), 200 * USD);
        leo.approve(USDC, address(pool), MAX_UINT);
        pat.finalize(address(pool));

        // Deposit 100 USDC on first day
        uint256 startDate = block.timestamp;

        uint256 initialAmt = 100 * USD;

        leo.deposit(address(pool), 100 * USD);
        assertEq(pool.depositDate(address(leo)), startDate);

        uint256 newAmt = 20 * USD;

        hevm.warp(startDate + 30 days);
        leo.deposit(address(pool), newAmt);

        uint256 newDepDate = startDate + (block.timestamp - startDate) * newAmt / (newAmt + initialAmt);
        assertEq(pool.depositDate(address(leo)), newDepDate);  // Gets updated

        assertTrue(pat.try_setLockupPeriod(address(pool), uint256(0)));  // Sets 0 as lockup period to allow withdraw. 
        make_withdrawable(leo, pool);
        leo.withdraw(address(pool), newAmt);

        assertEq(pool.depositDate(address(leo)), newDepDate);  // Doesn't change
    }

    function test_transfer_depositDate() public {
        address stakeLocker = pool.stakeLocker();

        pat.approve(address(bPool), stakeLocker, MAX_UINT);
        pat.stake(pool.stakeLocker(), bPool.balanceOf(address(pat)) / 2);
        pat.finalize(address(pool));
        pat.setOpenToPublic(address(pool), true);
        
        // Mint 200 USDC into this LP account
        mint("USDC", address(leo), 200 * USD);
        mint("USDC", address(liz), 200 * USD);
        leo.approve(USDC, address(pool), MAX_UINT);
        liz.approve(USDC, address(pool), MAX_UINT);
        
        // Deposit 100 USDC on first day
        uint256 startDate = block.timestamp;

        uint256 initialAmt = 100 * WAD;  // Amount of FDT minted on first deposit

        leo.deposit(address(pool), 100 * USD);
        liz.deposit(address(pool), 100 * USD);
        
        assertEq(pool.depositDate(address(leo)), startDate);
        assertEq(pool.depositDate(address(liz)), startDate);

        uint256 newAmt = 20 * WAD;  // Amount of FDT transferred

        hevm.warp(startDate + 30 days);

        assertEq(pool.balanceOf(address(leo)), initialAmt);
        assertEq(pool.balanceOf(address(liz)), initialAmt);

        // Pause protocol and attempt to transfer FDTs
        assertTrue( emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!liz.try_transfer(address(pool), address(leo), newAmt));

        // Unpause protocol and transfer FDTs
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(liz.try_transfer(address(pool), address(leo), newAmt));  // Pool.transfer()

        assertEq(pool.balanceOf(address(leo)), initialAmt + newAmt);
        assertEq(pool.balanceOf(address(liz)), initialAmt - newAmt);

        uint256 newDepDate = startDate + (block.timestamp - startDate) * newAmt / (newAmt + initialAmt);

        assertEq(pool.depositDate(address(leo)), newDepDate);  // Gets updated
        assertEq(pool.depositDate(address(liz)),  startDate);  // Stays the same
    }

    function test_transfer_recipient_withdrawing() public {
        address stakeLocker = pool.stakeLocker();

        pat.approve(address(bPool), stakeLocker, MAX_UINT);
        pat.stake(pool.stakeLocker(), bPool.balanceOf(address(pat)) / 2);
        pat.finalize(address(pool));
        pat.setOpenToPublic(address(pool), true);

        uint256 start = block.timestamp;
        uint256 deposit = 100;

        // Mint USDC into LP accounts
        mint("USDC", address(leo), deposit * USD);
        mint("USDC", address(liz), deposit * USD);
        leo.approve(USDC, address(pool), MAX_UINT);
        liz.approve(USDC, address(pool), MAX_UINT);

        // Deposit USDC into Pool
        leo.deposit(address(pool), deposit * USD);
        liz.deposit(address(pool), deposit * USD);
        assertEq(pool.balanceOf(address(leo)), deposit * WAD);
        assertEq(pool.balanceOf(address(liz)), deposit * WAD);
        assertEq(pool.depositDate(address(leo)), start);
        assertEq(pool.depositDate(address(liz)), start);

        // LP (Che) initiates withdrawal
        assertTrue(liz.try_intendToWithdraw(address(pool)), "Failed to intend to withdraw");
        assertEq(pool.withdrawCooldown(address(liz)), start);

        // LP (Bob) fails to transfer to LP (Che) who is currently withdrawing
        assertTrue(!leo.try_transfer(address(pool), address(liz), deposit * WAD));
        hevm.warp(start + globals.lpCooldownPeriod() + globals.lpWithdrawWindow());  // Very end of LP withdrawal window
        assertTrue(!leo.try_transfer(address(pool), address(liz), deposit * WAD));

        // LP (Bob) successfully transfers to LP (Che) who is outside withdraw window
        hevm.warp(start + globals.lpCooldownPeriod() + globals.lpWithdrawWindow() + 1);  // Second after LP withdrawal window ends
        assertTrue(leo.try_transfer(address(pool), address(liz), deposit * WAD));

        // Check balances and deposit dates are correct
        assertEq(pool.balanceOf(address(leo)), 0);
        assertEq(pool.balanceOf(address(liz)), deposit * WAD * 2);
        uint256 newDepDate = start + (block.timestamp - start) * (deposit * WAD) / ((deposit * WAD) + (deposit * WAD));
        assertEq(pool.depositDate(address(leo)), start);       // Stays the same
        assertEq(pool.depositDate(address(liz)), newDepDate);  // Gets updated
    }

    function test_fundLoan() public {
        address stakeLocker   = pool.stakeLocker();
        address liqLocker     = pool.liquidityLocker();
        address fundingLocker = loan.fundingLocker();

        pat.approve(address(bPool), stakeLocker, MAX_UINT);
        pat.stake(pool.stakeLocker(), bPool.balanceOf(address(pat)) / 2);

        // Mint 100 USDC into this LP account
        mint("USDC", address(leo), 100 * USD);

        pat.finalize(address(pool));
        pat.setOpenToPublic(address(pool), true);

        leo.approve(USDC, address(pool), MAX_UINT);

        assertTrue(leo.try_deposit(address(pool), 100 * USD));

        gov.setValidLoanFactory(address(loanFactory), false);

        assertTrue(!pat.try_fundLoan(address(pool), address(loan), address(dlFactory), 100 * USD)); // LoanFactory not in globals

        gov.setValidLoanFactory(address(loanFactory), true);

        assertEq(IERC20(USDC).balanceOf(liqLocker),               100 * USD);  // Balance of Liquidity Locker
        assertEq(IERC20(USDC).balanceOf(address(fundingLocker)),          0);  // Balance of Funding Locker
        
        /*******************/
        /*** Fund a Loan ***/
        /*******************/
        // Pause protocol and attempt fundLoan()
        assertTrue( emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!pat.try_fundLoan(address(pool), address(loan), address(dlFactory), 1 * USD));

        // Unpause protocol and fundLoan()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(pat.try_fundLoan(address(pool), address(loan), address(dlFactory), 20 * USD), "Fail to fund a loan");  // Fund loan for 20 USDC

        DebtLocker debtLocker = DebtLocker(pool.debtLockers(address(loan), address(dlFactory)));

        assertEq(address(debtLocker.loan()), address(loan));
        assertEq(debtLocker.pool(), address(pool));
        assertEq(address(debtLocker.liquidityAsset()), USDC);

        assertEq(IERC20(USDC).balanceOf(liqLocker),              80 * USD);  // Balance of Liquidity Locker
        assertEq(IERC20(USDC).balanceOf(address(fundingLocker)), 20 * USD);  // Balance of Funding Locker
        assertEq(IERC20(loan).balanceOf(address(debtLocker)),    20 * WAD);  // LoanToken balance of LT Locker
        assertEq(pool.principalOut(),                           20 * USD);  // Outstanding principal in liqiudity pool 1

        /****************************************/
        /*** Fund same loan with the same DL ***/
        /****************************************/
        assertTrue(pat.try_fundLoan(address(pool), address(loan), address(dlFactory), 25 * USD)); // Fund same loan for 25 USDC

        assertEq(dlFactory.owner(address(debtLocker)), address(pool));
        assertTrue(dlFactory.isLocker(address(debtLocker)));

        assertEq(IERC20(USDC).balanceOf(liqLocker),              55 * USD);  // Balance of Liquidity Locker
        assertEq(IERC20(USDC).balanceOf(address(fundingLocker)), 45 * USD);  // Balance of Funding Locker
        assertEq(IERC20(loan).balanceOf(address(debtLocker)),    45 * WAD);  // LoanToken balance of LT Locker
        assertEq(pool.principalOut(),                           45 * USD);  // Outstanding principal in liqiudity pool 1

        /*******************************************/
        /*** Fund same loan with a different DL ***/
        /*******************************************/
        assertTrue(pat.try_fundLoan(address(pool), address(loan), address(dlFactory2), 10 * USD)); // Fund loan for 15 USDC

        DebtLocker debtLocker2 = DebtLocker(pool.debtLockers(address(loan),  address(dlFactory2)));

        assertEq(address(debtLocker2.loan()), address(loan));
        assertEq(debtLocker2.pool(), address(pool));
        assertEq(address(debtLocker2.liquidityAsset()), USDC);

        assertEq(dlFactory2.owner(address(debtLocker2)), address(pool));
        assertTrue(dlFactory2.isLocker(address(debtLocker2)));

        assertEq(IERC20(USDC).balanceOf(liqLocker),              45 * USD);  // Balance of Liquidity Locker
        assertEq(IERC20(USDC).balanceOf(address(fundingLocker)), 55 * USD);  // Balance of Funding Locker
        assertEq(IERC20(loan).balanceOf(address(debtLocker2)),   10 * WAD);  // LoanToken balance of LT Locker 2
        assertEq(pool.principalOut(),                           55 * USD);  // Outstanding principal in liqiudity pool 1
    }

    function checkClaim(DebtLocker debtLocker, Loan _loan, PoolDelegate pd, IERC20 liquidityAsset, Pool pool, address dlFactory) internal {
        uint256[10] memory balances = [
            liquidityAsset.balanceOf(address(debtLocker)),
            liquidityAsset.balanceOf(address(pool)),
            liquidityAsset.balanceOf(address(pd)),
            liquidityAsset.balanceOf(pool.stakeLocker()),
            liquidityAsset.balanceOf(pool.liquidityLocker()),
            0,0,0,0,0
        ];

        uint256[4] memory loanData = [
            _loan.interestPaid(),
            _loan.principalPaid(),
            _loan.feePaid(),
            _loan.excessReturned()
        ];

        uint256[8] memory debtLockerData = [
            debtLocker.lastInterestPaid(),
            debtLocker.lastPrincipalPaid(),
            debtLocker.lastFeePaid(),
            debtLocker.lastExcessReturned(),
            0,0,0,0
        ];

        uint256 beforePrincipalOut = pool.principalOut();
        uint256 beforeInterestSum  = pool.interestSum();
        uint256[7] memory claim = pd.claim(address(pool), address(_loan),   address(dlFactory));

        // Updated DL state variables
        debtLockerData[4] = debtLocker.lastInterestPaid();
        debtLockerData[5] = debtLocker.lastPrincipalPaid();
        debtLockerData[6] = debtLocker.lastFeePaid();
        debtLockerData[7] = debtLocker.lastExcessReturned();

        balances[5] = liquidityAsset.balanceOf(address(debtLocker));
        balances[6] = liquidityAsset.balanceOf(address(pool));
        balances[7] = liquidityAsset.balanceOf(address(pd));
        balances[8] = liquidityAsset.balanceOf(pool.stakeLocker());
        balances[9] = liquidityAsset.balanceOf(pool.liquidityLocker());

        uint256 sumTransfer;
        uint256 sumNetNew;

        for(uint i = 0; i < 4; i++) sumNetNew += (loanData[i] - debtLockerData[i]);

        {
            for(uint i = 0; i < 4; i++) {
                assertEq(debtLockerData[i + 4], loanData[i]);  // DL updated to reflect loan state
                // Category portion of claim * DL asset balance 
                // Eg. (interestClaimed / totalClaimed) * balance = Portion of total claim balance that is interest
                uint256 loanShare = (loanData[i] - debtLockerData[i]) * claim[0] / sumNetNew;
                assertEq(loanShare, claim[i + 1]);

                sumTransfer += balances[i + 6] - balances[i + 1]; // Sum up all transfers that occured from claim
            }
            assertEq(claim[0], sumTransfer); // Assert balance from withdrawFunds equals sum of transfers
        }

        {
            assertEq(balances[5] - balances[0], 0);      // DL locker should have transferred ALL funds claimed to LP
            assertTrue(balances[6] - balances[1] < 10);  // LP        should have transferred ALL funds claimed to LL, SL, and PD (with rounding error)
            assertEq(balances[7] - balances[2], claim[3] + claim[1] * pool.delegateFee() / 10_000);  // Pool delegate claim (feePaid + delegateFee portion of interest)
            assertEq(balances[8] - balances[3],            claim[1] * pool.stakingFee()  / 10_000);  // Staking Locker claim (feePaid + stakingFee portion of interest)

            // Liquidity Locker balance change should EXACTLY equal state variable change
            assertEq(balances[9] - balances[4], (beforePrincipalOut - pool.principalOut()) + (pool.interestSum() - beforeInterestSum));

            // Normal case, principalClaim <= principalOut
            if (claim[2] + claim[4] <= beforePrincipalOut) {
                // interestSum incremented by remainder of interest
                withinPrecision(
                    pool.interestSum() - beforeInterestSum, 
                    claim[1] - claim[1] * (pool.delegateFee() + pool.stakingFee()) / 10_000, 
                    11
                );  
                // principalOut decremented by principal paid plus excess
                assertTrue(beforePrincipalOut - pool.principalOut() == claim[2] + claim[4]);
            } 
            // Edge case, attacker transfers funds into Loan to make principalClaim overflow
            else {
                // interestSum incremented by remainder of interest plus overflow amount
                withinPrecision(
                    pool.interestSum() - beforeInterestSum, 
                    claim[1] - claim[1] * (pool.delegateFee() + pool.stakingFee()) / 10_000 + (claim[2] + claim[4] - beforePrincipalOut), 
                    11
                );
                assertEq(pool.principalOut(), 0);
            }   
            
        }
    }

    function isConstantPoolValue(Pool pool, IERC20 liquidityAsset, uint256 constPoolVal) internal view returns(bool) {
        return pool.principalOut() + liquidityAsset.balanceOf(pool.liquidityLocker()) == constPoolVal;
    }

    function assertConstFundLoan(Pool pool, address _loan, address dlFactory, uint256 amt, IERC20 liquidityAsset, uint256 constPoolVal) internal returns(bool) {
        assertTrue(pat.try_fundLoan(address(pool), _loan,  dlFactory, amt));
        assertTrue(isConstantPoolValue(pool, liquidityAsset, constPoolVal));
    }

    function assertConstClaim(Pool pool, address _loan, address dlFactory, IERC20 liquidityAsset, uint256 constPoolVal) internal returns(bool) {
        pat.claim(address(pool), _loan, dlFactory);
        assertTrue(isConstantPoolValue(pool, liquidityAsset, constPoolVal));
    }

    function test_claim_defaulted_zero_collateral_loan() public {
        // Mint 10000 USDC into this LP account
        mint("USDC", address(lex), 10_000 * USD);
        lex.approve(USDC, address(pool), 10_000 * USD);

        // Set valid loan factory
        gov.setValidLoanFactory(address(loanFactory), true);

        // Finalizing the Pool
        pat.approve(address(bPool), pool.stakeLocker(), uint(-1));
        pat.stake(pool.stakeLocker(), bPool.balanceOf(address(pat)) / 2);
        pat.finalize(address(pool));
        pat.setOpenToPublic(address(pool), true);

        // Add liquidity
        assertTrue(lex.try_deposit(address(pool), 10_000 * USD));

        // Create Loan with 0% CR so no claimable funds are present after default
        uint256[5] memory specs = [500, 180, 30, uint256(1000 * USD), 0];
        address[3] memory calcs = [address(repaymentCalc), address(lateFeeCalc), address(premiumCalc)];

        Loan zero_loan = bob.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);

        // Fund the loan by pool delegate.
        assertTrue(pat.try_fundLoan(address(pool), address(zero_loan), address(dlFactory), 10_000 * USD));

        // Drawdown of the loan
        uint cReq = zero_loan.collateralRequiredForDrawdown(10_000 * USD); // wETH required for 15000 USDC drawdown on loan
        assertEq(cReq, 0); // No collateral required on 0% collateralized loan
        mint("WETH", address(bob), cReq);
        bob.approve(WETH, address(zero_loan),  cReq);
        bob.drawdown(address(zero_loan), 10_000 * USD);

        // Initial claim to clear out claimable funds
        uint256[7] memory claim = pat.claim(address(pool), address(zero_loan), address(dlFactory));

        // Time warp to default
        hevm.warp(block.timestamp + zero_loan.nextPaymentDue() + globals.defaultGracePeriod() + 1);
        pat.triggerDefault(address(pool), address(zero_loan), address(dlFactory));   // Triggers a "liquidation" that does not perform a swap

        uint256[7] memory claim2 = pat.claim(address(pool), address(zero_loan), address(dlFactory));
        assertEq(claim2[0], 0);
        assertEq(claim2[1], 0);
        assertEq(claim2[2], 0);
        assertEq(claim2[3], 0);
        assertEq(claim2[4], 0);
        assertEq(claim2[5], 0);
        assertEq(claim2[6], 10_000 * USD);
    }

    function test_claim_principal_accounting() public {
        /*********************************************/
        /*** Create a loan with 0% APR, 0% premium ***/
        /*********************************************/
        premiumCalc = new PremiumCalc(0); // Flat 0% premium
        gov.setCalc(address(premiumCalc), true);

        uint256[5] memory specs = [0, 180, 30, uint256(1000 * USD), 2000];
        address[3] memory calcs = [address(repaymentCalc), address(lateFeeCalc), address(premiumCalc)];

        loan  = bob.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);
        loan2 = ben.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);

        /*******************************/
        /*** Finalize liquidity pool ***/
        /*******************************/
        {
            pat.approve(address(bPool), pool.stakeLocker(), uint(-1));
            pat.stake(pool.stakeLocker(), bPool.balanceOf(address(pat)) / 2);

            pat.finalize(address(pool));
            pat.setOpenToPublic(address(pool), true);
        }
        /**************************************************/
        /*** Mint and deposit funds into liquidity pool ***/
        /**************************************************/
        {
            mint("USDC", address(leo), 1_000_000_000 * USD);
            mint("USDC", address(liz), 1_000_000_000 * USD);
            mint("USDC", address(lex), 1_000_000_000 * USD);

            leo.approve(USDC, address(pool), uint(-1));
            liz.approve(USDC, address(pool), uint(-1));
            lex.approve(USDC, address(pool), uint(-1));

            assertTrue(leo.try_deposit(address(pool), 100_000_000 * USD));  // 10%
            assertTrue(liz.try_deposit(address(pool), 300_000_000 * USD));  // 30%
            assertTrue(lex.try_deposit(address(pool), 600_000_000 * USD));  // 60%

            gov.setValidLoanFactory(address(loanFactory), true); // Don't remove, not done in setUp()
        }

        uint256 CONST_POOL_VALUE = pool.principalOut() + IERC20(USDC).balanceOf(pool.liquidityLocker());

        /************************************/
        /*** Fund loan / loan2 (Excess) ***/
        /************************************/
        {
            assertConstFundLoan(pool, address(loan),  address(dlFactory), 100_000_000 * USD, IERC20(USDC), CONST_POOL_VALUE);
            assertConstFundLoan(pool, address(loan),  address(dlFactory), 100_000_000 * USD, IERC20(USDC), CONST_POOL_VALUE);
            assertConstFundLoan(pool, address(loan),  address(dlFactory2), 200_000_000 * USD, IERC20(USDC), CONST_POOL_VALUE);
            assertConstFundLoan(pool, address(loan),  address(dlFactory2), 200_000_000 * USD, IERC20(USDC), CONST_POOL_VALUE);
            assertConstFundLoan(pool, address(loan2), address(dlFactory),  50_000_000 * USD, IERC20(USDC), CONST_POOL_VALUE);
            assertConstFundLoan(pool, address(loan2), address(dlFactory),  50_000_000 * USD, IERC20(USDC), CONST_POOL_VALUE);
            assertConstFundLoan(pool, address(loan2), address(dlFactory2), 150_000_000 * USD, IERC20(USDC), CONST_POOL_VALUE);
            assertConstFundLoan(pool, address(loan2), address(dlFactory2), 150_000_000 * USD, IERC20(USDC), CONST_POOL_VALUE);
        }
        
        assertEq(pool.principalOut(), 1_000_000_000 * USD);
        assertEq(IERC20(USDC).balanceOf(pool.liquidityLocker()), 0);

        /*****************/
        /*** Draw Down ***/
        /*****************/
        {
            uint cReq1 =  loan.collateralRequiredForDrawdown(100_000_000 * USD); // wETH required for 100_000_000 USDC drawdown on loan
            uint cReq2 = loan2.collateralRequiredForDrawdown(100_000_000 * USD); // wETH required for 100_000_000 USDC drawdown on loan2
            mint("WETH", address(bob), cReq1);
            mint("WETH", address(ben), cReq2);
            bob.approve(WETH, address(loan),  cReq1);
            ben.approve(WETH, address(loan2), cReq2);
            bob.drawdown(address(loan),  100_000_000 * USD);
            ben.drawdown(address(loan2), 100_000_000 * USD);
        }
        
        /*********************************/
        /*** Make (Early) Full Payment ***/
        /*********************************/
        {
            (uint amtf_1,,) =  loan.getFullPayment(); // USDC required for 2nd payment on loan
            (uint amtf_2,,) = loan2.getFullPayment(); // USDC required for 2nd payment on loan2
            mint("USDC", address(bob), amtf_1);
            mint("USDC", address(ben), amtf_2);
            bob.approve(USDC, address(loan),  amtf_1);
            ben.approve(USDC, address(loan2), amtf_2);
            bob.makeFullPayment(address(loan));
            ben.makeFullPayment(address(loan2));
        }
        
        /******************/
        /*** Pool Claim ***/
        /******************/
        {      
            assertConstClaim(pool, address(loan),  address(dlFactory), IERC20(USDC), CONST_POOL_VALUE);
            assertConstClaim(pool, address(loan),  address(dlFactory2), IERC20(USDC), CONST_POOL_VALUE);
            assertConstClaim(pool, address(loan2), address(dlFactory), IERC20(USDC), CONST_POOL_VALUE);
            assertConstClaim(pool, address(loan2), address(dlFactory2), IERC20(USDC), CONST_POOL_VALUE);
        }
        
        assertTrue(pool.principalOut() < 10);
    }

    function test_claim_singleLP() public {

        /*******************************/
        /*** Finalize liquidity pool ***/
        /*******************************/
        {
            pat.approve(address(bPool), pool.stakeLocker(), MAX_UINT);
            pat.stake(pool.stakeLocker(), bPool.balanceOf(address(pat)) / 2);

            pat.finalize(address(pool));
            pat.setOpenToPublic(address(pool), true);
        }
        /**************************************************/
        /*** Mint and deposit funds into liquidity pool ***/
        /**************************************************/
        {
            mint("USDC", address(leo), 1_000_000_000 * USD);
            mint("USDC", address(liz), 1_000_000_000 * USD);
            mint("USDC", address(lex), 1_000_000_000 * USD);

            leo.approve(USDC, address(pool), MAX_UINT);
            liz.approve(USDC, address(pool), MAX_UINT);
            lex.approve(USDC, address(pool), MAX_UINT);

            assertTrue(leo.try_deposit(address(pool), 100_000_000 * USD));  // 10%
            assertTrue(liz.try_deposit(address(pool), 300_000_000 * USD));  // 30%
            assertTrue(lex.try_deposit(address(pool), 600_000_000 * USD));  // 60%

            gov.setValidLoanFactory(address(loanFactory), true); // Don't remove, not done in setUp()
        }

        /************************************/
        /*** Fund loan / loan2 (Excess) ***/
        /************************************/
        {
            assertTrue(pat.try_fundLoan(address(pool), address(loan),  address(dlFactory), 100_000_000 * USD));
            assertTrue(pat.try_fundLoan(address(pool), address(loan),  address(dlFactory), 100_000_000 * USD));
            assertTrue(pat.try_fundLoan(address(pool), address(loan),  address(dlFactory2), 200_000_000 * USD));
            assertTrue(pat.try_fundLoan(address(pool), address(loan),  address(dlFactory2), 200_000_000 * USD));

            assertTrue(pat.try_fundLoan(address(pool), address(loan2), address(dlFactory),  50_000_000 * USD));
            assertTrue(pat.try_fundLoan(address(pool), address(loan2), address(dlFactory),  50_000_000 * USD));
            assertTrue(pat.try_fundLoan(address(pool), address(loan2), address(dlFactory2), 150_000_000 * USD));
            assertTrue(pat.try_fundLoan(address(pool), address(loan2), address(dlFactory2), 150_000_000 * USD));
        }

        assertEq(pool.principalOut(), 1_000_000_000 * USD);
        assertEq(IERC20(USDC).balanceOf(pool.liquidityLocker()), 0);

        DebtLocker debtLocker1 = DebtLocker(pool.debtLockers(address(loan),  address(dlFactory)));  // debtLocker1 = DebtLocker 1, for loan using dlFactory
        DebtLocker debtLocker2 = DebtLocker(pool.debtLockers(address(loan),  address(dlFactory2)));  // debtLocker2 = DebtLocker 2, for loan using dlFactory2
        DebtLocker debtLocker3 = DebtLocker(pool.debtLockers(address(loan2), address(dlFactory)));  // debtLocker3 = DebtLocker 3, for loan2 using dlFactory
        DebtLocker debtLocker4 = DebtLocker(pool.debtLockers(address(loan2), address(dlFactory2)));  // debtLocker4 = DebtLocker 4, for loan2 using dlFactory2

        /*****************/
        /*** Draw Down ***/
        /*****************/
        {
            uint cReq1 =  loan.collateralRequiredForDrawdown(100_000_000 * USD); // wETH required for 100_000_000 USDC drawdown on loan
            uint cReq2 = loan2.collateralRequiredForDrawdown(100_000_000 * USD); // wETH required for 100_000_000 USDC drawdown on loan2
            mint("WETH", address(bob), cReq1);
            mint("WETH", address(ben), cReq2);
            bob.approve(WETH, address(loan),  cReq1);
            ben.approve(WETH, address(loan2), cReq2);
            bob.drawdown(address(loan),  100_000_000 * USD);
            ben.drawdown(address(loan2), 100_000_000 * USD);
        }
        
        /****************************/
        /*** Make 1 Payment (1/6) ***/
        /****************************/
        {
            (uint amt1_1,,,,) =  loan.getNextPayment(); // USDC required for 1st payment on loan
            (uint amt1_2,,,,) = loan2.getNextPayment(); // USDC required for 1st payment on loan2
            mint("USDC", address(bob), amt1_1);
            mint("USDC", address(ben), amt1_2);
            bob.approve(USDC, address(loan),  amt1_1);
            ben.approve(USDC, address(loan2), amt1_2);
            bob.makePayment(address(loan));
            ben.makePayment(address(loan2));
        }
        
        /******************/
        /*** Pool Claim ***/
        /******************/
        {      
            checkClaim(debtLocker1, loan,  pat, IERC20(USDC), pool, address(dlFactory));
            checkClaim(debtLocker2, loan,  pat, IERC20(USDC), pool, address(dlFactory2));
            checkClaim(debtLocker3, loan2, pat, IERC20(USDC), pool, address(dlFactory));
            checkClaim(debtLocker4, loan2, pat, IERC20(USDC), pool, address(dlFactory2));
        }

        /******************************/
        /*** Make 2 Payments (3/6)  ***/
        /******************************/
        {
            (uint amt2_1,,,,) =  loan.getNextPayment(); // USDC required for 2nd payment on loan
            (uint amt2_2,,,,) = loan2.getNextPayment(); // USDC required for 2nd payment on loan2
            mint("USDC", address(bob), amt2_1);
            mint("USDC", address(ben), amt2_2);
            bob.approve(USDC, address(loan),  amt2_1);
            ben.approve(USDC, address(loan2), amt2_2);
            bob.makePayment(address(loan));
            ben.makePayment(address(loan2));

            (uint amt3_1,,,,) =  loan.getNextPayment(); // USDC required for 3rd payment on loan
            (uint amt3_2,,,,) = loan2.getNextPayment(); // USDC required for 3rd payment on loan2
            mint("USDC", address(bob), amt3_1);
            mint("USDC", address(ben), amt3_2);
            bob.approve(USDC, address(loan),  amt3_1);
            ben.approve(USDC, address(loan2), amt3_2);
            bob.makePayment(address(loan));
            ben.makePayment(address(loan2));
        }
        
        /******************/
        /*** Pool Claim ***/
        /******************/
        {      
            checkClaim(debtLocker1, loan,  pat, IERC20(USDC), pool, address(dlFactory));
            checkClaim(debtLocker2, loan,  pat, IERC20(USDC), pool, address(dlFactory2));
            checkClaim(debtLocker3, loan2, pat, IERC20(USDC), pool, address(dlFactory));
            checkClaim(debtLocker4, loan2, pat, IERC20(USDC), pool, address(dlFactory2));
        }
        
        /*********************************/
        /*** Make (Early) Full Payment ***/
        /*********************************/
        {
            (uint amtf_1,,) =  loan.getFullPayment(); // USDC required for 2nd payment on loan
            (uint amtf_2,,) = loan2.getFullPayment(); // USDC required for 2nd payment on loan2
            mint("USDC", address(bob), amtf_1);
            mint("USDC", address(ben), amtf_2);
            bob.approve(USDC, address(loan),  amtf_1);
            ben.approve(USDC, address(loan2), amtf_2);
            bob.makeFullPayment(address(loan));
            ben.makeFullPayment(address(loan2));
        }
        
        /******************/
        /*** Pool Claim ***/
        /******************/
        {      
            checkClaim(debtLocker1, loan,  pat, IERC20(USDC), pool, address(dlFactory));
            checkClaim(debtLocker2, loan,  pat, IERC20(USDC), pool, address(dlFactory2));
            checkClaim(debtLocker3, loan2, pat, IERC20(USDC), pool, address(dlFactory));
            checkClaim(debtLocker4, loan2, pat, IERC20(USDC), pool, address(dlFactory2));

            // Ensure both loans are matured.
            assertEq(uint256(loan.loanState()),  2);
            assertEq(uint256(loan2.loanState()), 2);
        }

        assertTrue(pool.principalOut() < 10);
    }
    
    function test_claim_multipleLP() public {

        /******************************************/
        /*** Stake & Finalize 2 Liquidity Pools ***/
        /******************************************/
        address stakeLocker1 = pool.stakeLocker();
        address stakeLocker2 = pool2.stakeLocker();
        {
            pat.approve(address(bPool), stakeLocker1, MAX_UINT);
            pam.approve(address(bPool), stakeLocker2, MAX_UINT);
            pat.stake(pool.stakeLocker(), bPool.balanceOf(address(pat)) / 2);
            pam.stake(pool2.stakeLocker(), bPool.balanceOf(address(pam)) / 2);
            pat.finalize(address(pool));
            pat.setOpenToPublic(address(pool), true);
            pam.finalize(address(pool2));
            pam.setOpenToPublic(address(pool2), true);
        }
       
        address liqLocker1 = pool.liquidityLocker();
        address liqLocker2 = pool2.liquidityLocker();

        /*************************************************************/
        /*** Mint and deposit funds into liquidity pools (1b each) ***/
        /*************************************************************/
        {
            mint("USDC", address(leo), 1_000_000_000 * USD);
            mint("USDC", address(liz), 1_000_000_000 * USD);
            mint("USDC", address(lex), 1_000_000_000 * USD);

            leo.approve(USDC, address(pool), MAX_UINT);
            liz.approve(USDC, address(pool), MAX_UINT);
            lex.approve(USDC, address(pool), MAX_UINT);

            leo.approve(USDC, address(pool2), MAX_UINT);
            liz.approve(USDC, address(pool2), MAX_UINT);
            lex.approve(USDC, address(pool2), MAX_UINT);

            assertTrue(leo.try_deposit(address(pool), 100_000_000 * USD));  // 10% BOB in LP1
            assertTrue(liz.try_deposit(address(pool), 300_000_000 * USD));  // 30% CHE in LP1
            assertTrue(lex.try_deposit(address(pool), 600_000_000 * USD));  // 60% DAN in LP1

            assertTrue(leo.try_deposit(address(pool2), 500_000_000 * USD));  // 50% BOB in LP2
            assertTrue(liz.try_deposit(address(pool2), 400_000_000 * USD));  // 40% BOB in LP2
            assertTrue(lex.try_deposit(address(pool2), 100_000_000 * USD));  // 10% BOB in LP2

            gov.setValidLoanFactory(address(loanFactory), true); // Don't remove, not done in setUp()
        }
        
        address fundingLocker  = loan.fundingLocker();
        address fundingLocker2 = loan2.fundingLocker();

        /***************************/
        /*** Fund loan / loan2 ***/
        /***************************/
        {
            // LP 1 Vault 1
            assertTrue(pat.try_fundLoan(address(pool), address(loan),  address(dlFactory), 25_000_000 * USD));  // Fund loan using dlFactory for 25m USDC
            assertTrue(pat.try_fundLoan(address(pool), address(loan),  address(dlFactory), 25_000_000 * USD));  // Fund loan using dlFactory for 25m USDC, again, 50m USDC total
            assertTrue(pat.try_fundLoan(address(pool), address(loan),  address(dlFactory2), 25_000_000 * USD));  // Fund loan using dlFactory2 for 25m USDC
            assertTrue(pat.try_fundLoan(address(pool), address(loan),  address(dlFactory2), 25_000_000 * USD));  // Fund loan using dlFactory2 for 25m USDC (no excess), 100m USDC total

            // LP 2 Vault 1
            assertTrue(pam.try_fundLoan(address(pool2), address(loan),  address(dlFactory), 50_000_000 * USD));  // Fund loan using dlFactory for 50m USDC (excess), 150m USDC total
            assertTrue(pam.try_fundLoan(address(pool2), address(loan),  address(dlFactory2), 50_000_000 * USD));  // Fund loan using dlFactory2 for 50m USDC (excess), 200m USDC total

            // LP 1 Vault 2
            assertTrue(pat.try_fundLoan(address(pool), address(loan2),  address(dlFactory), 50_000_000 * USD));  // Fund loan2 using dlFactory for 50m USDC
            assertTrue(pat.try_fundLoan(address(pool), address(loan2),  address(dlFactory), 50_000_000 * USD));  // Fund loan2 using dlFactory for 50m USDC, again, 100m USDC total
            assertTrue(pat.try_fundLoan(address(pool), address(loan2),  address(dlFactory2), 50_000_000 * USD));  // Fund loan2 using dlFactory2 for 50m USDC
            assertTrue(pat.try_fundLoan(address(pool), address(loan2),  address(dlFactory2), 50_000_000 * USD));  // Fund loan2 using dlFactory2 for 50m USDC again, 200m USDC total

            // LP 2 Vault 2
            assertTrue(pam.try_fundLoan(address(pool2), address(loan2),  address(dlFactory), 100_000_000 * USD));  // Fund loan2 using dlFactory for 100m USDC
            assertTrue(pam.try_fundLoan(address(pool2), address(loan2),  address(dlFactory), 100_000_000 * USD));  // Fund loan2 using dlFactory for 100m USDC, again, 400m USDC total
            assertTrue(pam.try_fundLoan(address(pool2), address(loan2),  address(dlFactory2), 100_000_000 * USD));  // Fund loan2 using dlFactory2 for 100m USDC (excess)
            assertTrue(pam.try_fundLoan(address(pool2), address(loan2),  address(dlFactory2), 100_000_000 * USD));  // Fund loan2 using dlFactory2 for 100m USDC (excess), 600m USDC total
        }
        
        DebtLocker debtLocker1_pool1 = DebtLocker(pool.debtLockers(address(loan),  address(dlFactory)));  // debtLocker1_pool1 = DebtLocker 1, for pool, for loan using dlFactory
        DebtLocker debtLocker2_pool1 = DebtLocker(pool.debtLockers(address(loan),  address(dlFactory2)));  // debtLocker2_pool1 = DebtLocker 2, for pool, for loan using dlFactory2
        DebtLocker debtLocker3_pool1 = DebtLocker(pool.debtLockers(address(loan2), address(dlFactory)));  // debtLocker3_pool1 = DebtLocker 3, for pool, for loan2 using dlFactory
        DebtLocker debtLocker4_pool1 = DebtLocker(pool.debtLockers(address(loan2), address(dlFactory2)));  // debtLocker4_pool1 = DebtLocker 4, for pool, for loan2 using dlFactory2
        DebtLocker debtLocker1_pool2 = DebtLocker(pool2.debtLockers(address(loan),  address(dlFactory)));  // debtLocker1_pool2 = DebtLocker 1, for pool2, for loan using dlFactory
        DebtLocker debtLocker2_pool2 = DebtLocker(pool2.debtLockers(address(loan),  address(dlFactory2)));  // debtLocker2_pool2 = DebtLocker 2, for pool2, for loan using dlFactory2
        DebtLocker debtLocker3_pool2 = DebtLocker(pool2.debtLockers(address(loan2), address(dlFactory)));  // debtLocker3_pool2 = DebtLocker 3, for pool2, for loan2 using dlFactory
        DebtLocker debtLocker4_pool2 = DebtLocker(pool2.debtLockers(address(loan2), address(dlFactory2)));  // debtLocker4_pool2 = DebtLocker 4, for pool2, for loan2 using dlFactory2

        // Present state checks
        assertEq(IERC20(USDC).balanceOf(liqLocker1),              700_000_000 * USD);  // 1b USDC deposited - (100m USDC - 200m USDC)
        assertEq(IERC20(USDC).balanceOf(liqLocker2),              500_000_000 * USD);  // 1b USDC deposited - (100m USDC - 400m USDC)
        assertEq(IERC20(USDC).balanceOf(address(fundingLocker)),  200_000_000 * USD);  // Balance of loan fl 
        assertEq(IERC20(USDC).balanceOf(address(fundingLocker2)), 600_000_000 * USD);  // Balance of loan2 fl (no excess, exactly 400 USDC from LP1 & 600 USDC from LP2)
        assertEq(loan.balanceOf(address(debtLocker1_pool1)),       50_000_000 ether);  // Balance of debtLocker1 for pool with dlFactory
        assertEq(loan.balanceOf(address(debtLocker2_pool1)),       50_000_000 ether);  // Balance of debtLocker2 for pool with dlFactory2
        assertEq(loan2.balanceOf(address(debtLocker3_pool1)),     100_000_000 ether);  // Balance of debtLocker3 for pool with dlFactory
        assertEq(loan2.balanceOf(address(debtLocker4_pool1)),     100_000_000 ether);  // Balance of debtLocker4 for pool with dlFactory2
        assertEq(loan.balanceOf(address(debtLocker1_pool2)),       50_000_000 ether);  // Balance of debtLocker1 for pool2 with dlFactory
        assertEq(loan.balanceOf(address(debtLocker2_pool2)),       50_000_000 ether);  // Balance of debtLocker2 for pool2 with dlFactory2
        assertEq(loan2.balanceOf(address(debtLocker3_pool2)),     200_000_000 ether);  // Balance of debtLocker3 for pool2 with dlFactory
        assertEq(loan2.balanceOf(address(debtLocker4_pool2)),     200_000_000 ether);  // Balance of debtLocker4 for pool2 with dlFactory2

        /*****************/
        /*** Draw Down ***/
        /*****************/
        {
            uint cReq1 =  loan.collateralRequiredForDrawdown(500_000_000 * USD); // wETH required for 500m USDC drawdown on loan
            uint cReq2 = loan2.collateralRequiredForDrawdown(400_000_000 * USD); // wETH required for 500m USDC drawdown on loan2
            mint("WETH", address(bob), cReq1);
            mint("WETH", address(ben), cReq2);
            bob.approve(WETH, address(loan),  cReq1);
            ben.approve(WETH, address(loan2), cReq2);
            bob.drawdown(address(loan),  100_000_000 * USD); // 100m excess to be returned
            ben.drawdown(address(loan2), 300_000_000 * USD); // 200m excess to be returned
        }

        
        /****************************/
        /*** Make 1 Payment (1/6) ***/
        /****************************/
        {
            (uint amt1_1,,,,) =  loan.getNextPayment(); // USDC required for 1st payment on loan
            (uint amt1_2,,,,) = loan2.getNextPayment(); // USDC required for 1st payment on loan2
            mint("USDC", address(bob), amt1_1);
            mint("USDC", address(ben), amt1_2);
            bob.approve(USDC, address(loan),  amt1_1);
            ben.approve(USDC, address(loan2), amt1_2);
            bob.makePayment(address(loan));
            ben.makePayment(address(loan2));
        }
        
        /*******************/
        /***  Pool Claim ***/
        /*******************/
        {
            checkClaim(debtLocker1_pool1, loan,  pat, IERC20(USDC), pool, address(dlFactory));
            checkClaim(debtLocker2_pool1, loan,  pat, IERC20(USDC), pool, address(dlFactory2));
            checkClaim(debtLocker3_pool1, loan2, pat, IERC20(USDC), pool, address(dlFactory));
            checkClaim(debtLocker4_pool1, loan2, pat, IERC20(USDC), pool, address(dlFactory2));

            checkClaim(debtLocker1_pool2, loan,  pam, IERC20(USDC), pool2, address(dlFactory));
            checkClaim(debtLocker2_pool2, loan,  pam, IERC20(USDC), pool2, address(dlFactory2));
            checkClaim(debtLocker3_pool2, loan2, pam, IERC20(USDC), pool2, address(dlFactory));
            checkClaim(debtLocker4_pool2, loan2, pam, IERC20(USDC), pool2, address(dlFactory2));
        }

        /******************************/
        /*** Make 2 Payments (3/6)  ***/
        /******************************/
        {
            (uint amt2_1,,,,) =  loan.getNextPayment(); // USDC required for 2nd payment on loan
            (uint amt2_2,,,,) = loan2.getNextPayment(); // USDC required for 2nd payment on loan2
            mint("USDC", address(bob), amt2_1);
            mint("USDC", address(ben), amt2_2);
            bob.approve(USDC, address(loan),  amt2_1);
            ben.approve(USDC, address(loan2), amt2_2);
            bob.makePayment(address(loan));
            ben.makePayment(address(loan2));

            (uint amt3_1,,,,) =  loan.getNextPayment(); // USDC required for 3rd payment on loan
            (uint amt3_2,,,,) = loan2.getNextPayment(); // USDC required for 3rd payment on loan2
            mint("USDC", address(bob), amt3_1);
            mint("USDC", address(ben), amt3_2);
            bob.approve(USDC, address(loan),  amt3_1);
            ben.approve(USDC, address(loan2), amt3_2);
            bob.makePayment(address(loan));
            ben.makePayment(address(loan2));
        }

        /*******************/
        /***  Pool Claim ***/
        /*******************/
        {
            checkClaim(debtLocker1_pool1, loan,  pat, IERC20(USDC), pool, address(dlFactory));
            checkClaim(debtLocker2_pool1, loan,  pat, IERC20(USDC), pool, address(dlFactory2));
            checkClaim(debtLocker3_pool1, loan2, pat, IERC20(USDC), pool, address(dlFactory));
            checkClaim(debtLocker4_pool1, loan2, pat, IERC20(USDC), pool, address(dlFactory2));

            checkClaim(debtLocker1_pool2, loan,  pam, IERC20(USDC), pool2, address(dlFactory));
            checkClaim(debtLocker2_pool2, loan,  pam, IERC20(USDC), pool2, address(dlFactory2));
            checkClaim(debtLocker3_pool2, loan2, pam, IERC20(USDC), pool2, address(dlFactory));
            checkClaim(debtLocker4_pool2, loan2, pam, IERC20(USDC), pool2, address(dlFactory2));
        }
        
        /*********************************/
        /*** Make (Early) Full Payment ***/
        /*********************************/
        {
            (uint amtf_1,,) =  loan.getFullPayment(); // USDC required for 2nd payment on loan
            (uint amtf_2,,) = loan2.getFullPayment(); // USDC required for 2nd payment on loan2
            mint("USDC", address(bob), amtf_1);
            mint("USDC", address(ben), amtf_2);
            bob.approve(USDC, address(loan),  amtf_1);
            ben.approve(USDC, address(loan2), amtf_2);
            bob.makeFullPayment(address(loan));
            ben.makeFullPayment(address(loan2));
        }
        
        /*******************/
        /***  Pool Claim ***/
        /*******************/
        {
            checkClaim(debtLocker1_pool1, loan,  pat, IERC20(USDC), pool, address(dlFactory));
            checkClaim(debtLocker2_pool1, loan,  pat, IERC20(USDC), pool, address(dlFactory2));
            checkClaim(debtLocker3_pool1, loan2, pat, IERC20(USDC), pool, address(dlFactory));
            checkClaim(debtLocker4_pool1, loan2, pat, IERC20(USDC), pool, address(dlFactory2));

            checkClaim(debtLocker1_pool2, loan,  pam, IERC20(USDC), pool2, address(dlFactory));
            checkClaim(debtLocker2_pool2, loan,  pam, IERC20(USDC), pool2, address(dlFactory2));
            checkClaim(debtLocker3_pool2, loan2, pam, IERC20(USDC), pool2, address(dlFactory));
            checkClaim(debtLocker4_pool2, loan2, pam, IERC20(USDC), pool2, address(dlFactory2));

            // Ensure both loans are matured.
            assertEq(uint256(loan.loanState()),  2);
            assertEq(uint256(loan2.loanState()), 2);
        }

        assertTrue(pool.principalOut() < 10);
        assertTrue(pool2.principalOut() < 10);
    }

    function test_claim_external_transfers() public {
        /*******************************/
        /*** Finalize liquidity pool ***/
        /*******************************/
        {
            pat.approve(address(bPool), pool.stakeLocker(), uint(-1));
            pat.stake(pool.stakeLocker(), bPool.balanceOf(address(pat)) / 2);

            pat.finalize(address(pool));
            pat.setOpenToPublic(address(pool), true);
            gov.setValidLoanFactory(address(loanFactory), true); // Don't remove, not done in setUp()
        }

        /**********************************************************/
        /*** Mint, deposit funds into liquidity pool, fund loan ***/
        /**********************************************************/
        {
            mint("USDC", address(leo), 1_000_000_000 * USD);
            leo.approve(USDC, address(pool), uint(-1));
            leo.approve(USDC, address(this),  uint(-1));
            leo.deposit(address(pool), 100_000_000 * USD);
            pat.fundLoan(address(pool), address(loan),  address(dlFactory), 100_000_000 * USD);
            assertTrue(pool.debtLockers(address(loan), address(dlFactory)) != address(0));
            assertEq(pool.principalOut(), 100_000_000 * USD);
        }

        /*****************/
        /*** Draw Down ***/
        /*****************/
        {
            uint cReq1 =  loan.collateralRequiredForDrawdown(100_000_000 * USD); // wETH required for 100_000_000 USDC drawdown on loan
            mint("WETH", address(bob), cReq1);
            bob.approve(WETH, address(loan),  cReq1);
            bob.drawdown(address(loan),  100_000_000 * USD);
        }

        /*****************************/
        /*** Make Interest Payment ***/
        /*****************************/
        {
            (uint amt,,,,) =  loan.getNextPayment(); // USDC required for 1st payment on loan
            mint("USDC", address(bob), amt);
            bob.approve(USDC, address(loan),  amt);
            bob.makePayment(address(loan));
        }

        /****************************************************/
        /*** Transfer USDC into Pool, Loan and debtLocker ***/
        /****************************************************/
        {
            DebtLocker debtLocker1 = DebtLocker(pool.debtLockers(address(loan),  address(dlFactory)));

            uint256 poolBal_before       = IERC20(USDC).balanceOf(address(pool));
            uint256 debtLockerBal_before = IERC20(USDC).balanceOf(address(debtLocker1));

            IERC20(USDC).transferFrom(address(leo), address(pool),       1000 * USD);
            IERC20(USDC).transferFrom(address(leo), address(debtLocker1), 2000 * USD);
            IERC20(USDC).transferFrom(address(leo), address(loan),        2000 * USD);

            uint256 poolBal_after       = IERC20(USDC).balanceOf(address(pool));
            uint256 debtLockerBal_after = IERC20(USDC).balanceOf(address(debtLocker1));

            assertEq(poolBal_after - poolBal_before,             1000 * USD);
            assertEq(debtLockerBal_after - debtLockerBal_before, 2000 * USD);

            poolBal_before       = poolBal_after;
            debtLockerBal_before = debtLockerBal_after;

            checkClaim(debtLocker1, loan, pat, IERC20(USDC), pool, address(dlFactory));

            poolBal_after       = IERC20(USDC).balanceOf(address(pool));
            debtLockerBal_after = IERC20(USDC).balanceOf(address(debtLocker1));

            assertTrue(poolBal_after - poolBal_before < 10);  // Collects some rounding dust
            assertEq(debtLockerBal_after, debtLockerBal_before);
        }

        /*************************/
        /*** Make Full Payment ***/
        /*************************/
        {
            (uint amt,,) =  loan.getFullPayment(); // USDC required for 1st payment on loan
            mint("USDC", address(bob), amt);
            bob.approve(USDC, address(loan),  amt);
            bob.makeFullPayment(address(loan));
        }

        /*********************************************************/
        /*** Check claim with existing balances in DL and Pool ***/
        /*** Transfer more funds into Loan                     ***/
        /*********************************************************/
        {
            DebtLocker debtLocker1 = DebtLocker(pool.debtLockers(address(loan),  address(dlFactory)));

            // Transfer funds into Loan to make principalClaim > principalOut
            ERC20(USDC).transferFrom(address(leo), address(loan), 200000 * USD);

            uint256 poolBal_before       = IERC20(USDC).balanceOf(address(pool));
            uint256 debtLockerBal_before = IERC20(USDC).balanceOf(address(debtLocker1));

            checkClaim(debtLocker1, loan, pat, IERC20(USDC), pool, address(dlFactory));

            uint256 poolBal_after       = IERC20(USDC).balanceOf(address(pool));
            uint256 debtLockerBal_after = IERC20(USDC).balanceOf(address(debtLocker1));

            assertTrue(poolBal_after - poolBal_before < 10);  // Collects some rounding dust
            assertEq(debtLockerBal_after, debtLockerBal_before);
        }

        assertTrue(pool.principalOut() < 10);
    }

    function setUpWithdraw() internal {
        /*******************************/
        /*** Finalize liquidity pool ***/
        /*******************************/
        {
            pat.approve(address(bPool), pool.stakeLocker(), MAX_UINT);
            pat.stake(pool.stakeLocker(), bPool.balanceOf(address(pat)) / 2);
            pat.setOpenToPublic(address(pool), true);
            pat.finalize(address(pool));
        }
        /**************************************************/
        /*** Mint and deposit funds into liquidity pool ***/
        /**************************************************/
        {
            mint("USDC", address(leo), 1_000_000_000 * USD);
            mint("USDC", address(liz), 1_000_000_000 * USD);
            mint("USDC", address(lex), 1_000_000_000 * USD);

            leo.approve(USDC, address(pool), MAX_UINT);
            liz.approve(USDC, address(pool), MAX_UINT);
            lex.approve(USDC, address(pool), MAX_UINT);

            assertTrue(leo.try_deposit(address(pool), 100_000_000 * USD));  // 10%
            assertTrue(liz.try_deposit(address(pool), 300_000_000 * USD));  // 30%
            assertTrue(lex.try_deposit(address(pool), 600_000_000 * USD));  // 60%

            gov.setValidLoanFactory(address(loanFactory), true); // Don't remove, not done in setUp()
        }

        /************************************/
        /*** Fund loan / loan2 (Excess) ***/
        /************************************/
        {
            assertTrue(pat.try_fundLoan(address(pool), address(loan),  address(dlFactory), 100_000_000 * USD));
            assertTrue(pat.try_fundLoan(address(pool), address(loan),  address(dlFactory), 100_000_000 * USD));
            assertTrue(pat.try_fundLoan(address(pool), address(loan),  address(dlFactory2), 200_000_000 * USD));
            assertTrue(pat.try_fundLoan(address(pool), address(loan),  address(dlFactory2), 200_000_000 * USD));

            assertTrue(pat.try_fundLoan(address(pool), address(loan2), address(dlFactory),  50_000_000 * USD));
            assertTrue(pat.try_fundLoan(address(pool), address(loan2), address(dlFactory),  50_000_000 * USD));
            assertTrue(pat.try_fundLoan(address(pool), address(loan2), address(dlFactory2), 150_000_000 * USD));
            assertTrue(pat.try_fundLoan(address(pool), address(loan2), address(dlFactory2), 150_000_000 * USD));
        }

        /*****************/
        /*** Draw Down ***/
        /*****************/
        {
            uint cReq1 =  loan.collateralRequiredForDrawdown(100_000_000 * USD); // wETH required for 100_000_000 USDC drawdown on loan
            uint cReq2 = loan2.collateralRequiredForDrawdown(100_000_000 * USD); // wETH required for 100_000_000 USDC drawdown on loan2
            mint("WETH", address(bob), cReq1);
            mint("WETH", address(ben), cReq2);
            bob.approve(WETH, address(loan),  cReq1);
            ben.approve(WETH, address(loan2), cReq2);
            bob.drawdown(address(loan),  100_000_000 * USD);
            ben.drawdown(address(loan2), 100_000_000 * USD);
        }
        
        /****************************/
        /*** Make 1 Payment (1/6) ***/
        /****************************/
        {
            (uint amt1_1,,,,) =  loan.getNextPayment(); // USDC required for 1st payment on loan
            (uint amt1_2,,,,) = loan2.getNextPayment(); // USDC required for 1st payment on loan2
            mint("USDC", address(bob), amt1_1);
            mint("USDC", address(ben), amt1_2);
            bob.approve(USDC, address(loan),  amt1_1);
            ben.approve(USDC, address(loan2), amt1_2);
            bob.makePayment(address(loan));
            ben.makePayment(address(loan2));
        }
        
        /******************/
        /*** Pool Claim ***/
        /******************/
        {   
            pat.claim(address(pool), address(loan),  address(dlFactory));
            pat.claim(address(pool), address(loan),  address(dlFactory2));
            pat.claim(address(pool), address(loan2), address(dlFactory));
            pat.claim(address(pool), address(loan2), address(dlFactory2));
        }

        /******************************/
        /*** Make 2 Payments (3/6)  ***/
        /******************************/
        {
            (uint amt2_1,,,,) =  loan.getNextPayment(); // USDC required for 2nd payment on loan
            (uint amt2_2,,,,) = loan2.getNextPayment(); // USDC required for 2nd payment on loan2
            mint("USDC", address(bob), amt2_1);
            mint("USDC", address(ben), amt2_2);
            bob.approve(USDC, address(loan),  amt2_1);
            ben.approve(USDC, address(loan2), amt2_2);
            bob.makePayment(address(loan));
            ben.makePayment(address(loan2));

            (uint amt3_1,,,,) =  loan.getNextPayment(); // USDC required for 3rd payment on loan
            (uint amt3_2,,,,) = loan2.getNextPayment(); // USDC required for 3rd payment on loan2
            mint("USDC", address(bob), amt3_1);
            mint("USDC", address(ben), amt3_2);
            bob.approve(USDC, address(loan),  amt3_1);
            ben.approve(USDC, address(loan2), amt3_2);
            bob.makePayment(address(loan));
            ben.makePayment(address(loan2));
        }
        
        /******************/
        /*** Pool Claim ***/
        /******************/
        {      
            pat.claim(address(pool), address(loan),  address(dlFactory));
            pat.claim(address(pool), address(loan),  address(dlFactory2));
            pat.claim(address(pool), address(loan2), address(dlFactory));
            pat.claim(address(pool), address(loan2), address(dlFactory2));
        }
        
        /*********************************/
        /*** Make (Early) Full Payment ***/
        /*********************************/
        {
            (uint amtf_1,,) =  loan.getFullPayment(); // USDC required for 2nd payment on loan
            (uint amtf_2,,) = loan2.getFullPayment(); // USDC required for 2nd payment on loan2
            mint("USDC", address(bob), amtf_1);
            mint("USDC", address(ben), amtf_2);
            bob.approve(USDC, address(loan),  amtf_1);
            ben.approve(USDC, address(loan2), amtf_2);
            bob.makeFullPayment(address(loan));
            ben.makeFullPayment(address(loan2));
        }
        
        /******************/
        /*** Pool Claim ***/
        /******************/
        {   
            pat.claim(address(pool), address(loan),  address(dlFactory));
            pat.claim(address(pool), address(loan),  address(dlFactory2));
            pat.claim(address(pool), address(loan2), address(dlFactory));
            pat.claim(address(pool), address(loan2), address(dlFactory2));

            // Ensure both loans are matured.
            assertEq(uint256(loan.loanState()),  2);
            assertEq(uint256(loan2.loanState()), 2);
        }
    }

    function test_withdraw_cooldown() public {

        gov.setLpCooldownPeriod(10 days);

        address stakeLocker = pool.stakeLocker();

        pat.approve(address(bPool), stakeLocker, MAX_UINT);
        pat.stake(pool.stakeLocker(), bPool.balanceOf(address(pat)) / 2);

        // Mint 1000 USDC into this LP account
        mint("USDC", address(leo), 10000 * USD);

        pat.finalize(address(pool));
        pat.setLockupPeriod(address(pool), 0); 
        pat.setOpenToPublic(address(pool), true);

        leo.approve(USDC, address(pool), MAX_UINT);

        leo.deposit(address(pool), 1500 * USD);

        uint256 amt = 500 * USD; // 1/3 of deposit so withdraw can happen thrice

        uint256 start = block.timestamp;

        assertTrue(!leo.try_withdraw(address(pool), amt),    "Should fail to withdraw 500 USD because user has to intendToWithdraw");
        assertTrue(!lex.try_intendToWithdraw(address(pool)), "Failed to intend to withdraw because lex has zero pool FDTs");
        assertTrue( leo.try_intendToWithdraw(address(pool)), "Failed to intend to withdraw");
        assertEq( pool.withdrawCooldown(address(leo)), start);
        assertTrue(!leo.try_withdraw(address(pool), amt), "Should fail to withdraw as cooldown period hasn't passed yet");

        // Just before cooldown ends
        hevm.warp(start + globals.lpCooldownPeriod() - 1);
        assertTrue(!leo.try_withdraw(address(pool), amt), "Should fail to withdraw as cooldown period hasn't passed yet");

        // Right when cooldown ends
        hevm.warp(start + globals.lpCooldownPeriod());
        assertTrue(leo.try_withdraw(address(pool), amt), "Should be able to withdraw funds at beginning of cooldown window");

        // Still within LP withdrawal window
        hevm.warp(start + globals.lpCooldownPeriod() + 1);
        assertTrue(leo.try_withdraw(address(pool), amt), "Should be able to withdraw funds again during cooldown window");

        // Second after LP withdrawal window ends
        hevm.warp(start + globals.lpCooldownPeriod() + globals.lpWithdrawWindow() + 1);
        assertTrue(!leo.try_withdraw(address(pool), amt), "Should fail to withdraw funds because now past withdraw window");

        uint256 newStart = block.timestamp;

        // Intend to withdraw
        assertTrue(leo.try_intendToWithdraw(address(pool)), "Failed to intend to withdraw");

        // Second after LP withdrawal window ends
        hevm.warp(newStart + globals.lpCooldownPeriod() + globals.lpWithdrawWindow() + 1);
        assertTrue(!leo.try_withdraw(address(pool), amt), "Should fail to withdraw as cooldown window has been passed");

        // Last second of LP withdrawal window
        hevm.warp(newStart + globals.lpCooldownPeriod() + globals.lpWithdrawWindow());
        assertTrue(leo.try_withdraw(address(pool), amt), "Should be able to withdraw funds at end of cooldown window");
    }

    function test_cancelWithdraw() public {

        setUpWithdraw();

        // Mint USDC to lee and deposit into Pool
        mint("USDC", address(lee), 1000 * USD);
        lee.approve(USDC, address(pool), MAX_UINT);
        assertTrue(lee.try_deposit(address(pool), 1000 * USD));

        assertEq(pool.withdrawCooldown(address(lee)), 0);
        assertTrue(lee.try_intendToWithdraw(address(pool)));
        assertEq(pool.withdrawCooldown(address(lee)), block.timestamp);

        assertTrue(lee.try_cancelWithdraw(address(pool)));
        assertEq(pool.withdrawCooldown(address(lee)), 0);
    }

    function test_withdraw_under_lockup_period() public {
        setUpWithdraw();

        // Ignore cooldown for this test
        gov.setLpWithdrawWindow(MAX_UINT);

        uint start = block.timestamp;

        // Mint USDC to lee
        mint("USDC", address(lee), 5000 * USD);
        lee.approve(USDC, address(pool), MAX_UINT);
        uint256 bal0 = IERC20(USDC).balanceOf(address(lee));
        
        // Deposit 1000 USDC and check depositDate
        assertTrue(lee.try_deposit(address(pool), 1000 * USD));
        assertEq(pool.depositDate(address(lee)), start);

        // Fund loan, drawdown, make payment and claim so lee can claim interest
        assertTrue(pat.try_fundLoan(address(pool), address(loan3),  address(dlFactory), 1000 * USD), "Fail to fund the loan");
        _drawDownLoan(1000 * USD, loan3, bud);
        _makeLoanPayment(loan3, bud); 
        pat.claim(address(pool), address(loan3), address(dlFactory));

        uint256 interest = pool.withdrawableFundsOf(address(lee));  // Get kims withdrawable funds

        assertTrue(lee.try_intendToWithdraw(address(pool)));
        // Warp to exact time that lee can withdraw with weighted deposit date
        hevm.warp(pool.depositDate(address(lee)) + pool.lockupPeriod() - 1);
        assertTrue(!lee.try_withdraw(address(pool), 1000 * USD), "Withdraw failure didn't trigger");
        hevm.warp(pool.depositDate(address(lee)) + pool.lockupPeriod());
        assertTrue( lee.try_withdraw(address(pool), 1000 * USD), "Failed to withdraw funds");

        assertEq(IERC20(USDC).balanceOf(address(lee)) - bal0, interest);
    }

    function test_withdraw_under_weighted_lockup_period() public {
        setUpWithdraw();

        // Ignore cooldown for this test
        gov.setLpWithdrawWindow(MAX_UINT);

        uint start = block.timestamp;

        // Mint USDC to lee
        mint("USDC", address(lee), 5000 * USD);
        lee.approve(USDC, address(pool), MAX_UINT);
        uint256 bal0 = IERC20(USDC).balanceOf(address(lee));

        // Deposit 1000 USDC and check depositDate
        assertTrue(lee.try_deposit(address(pool), 1000 * USD));
        assertEq(pool.depositDate(address(lee)), start);

        // Fund loan, drawdown, make payment and claim so lee can claim interest
        assertTrue(pat.try_fundLoan(address(pool), address(loan3),  address(dlFactory), 1000 * USD), "Fail to fund the loan");
        _drawDownLoan(1000 * USD, loan3, bud);
        _makeLoanPayment(loan3, bud); 
        pat.claim(address(pool), address(loan3), address(dlFactory));

        // Warp to exact time that lee can withdraw for the first time
        hevm.warp(start + pool.lockupPeriod());  
        assertEq(block.timestamp - pool.depositDate(address(lee)), pool.lockupPeriod());  // Can withdraw at this point
        
        // Deposit more USDC into pool, increasing deposit date and locking up funds again
        assertTrue(lee.try_deposit(address(pool), 3000 * USD));
        assertEq(pool.depositDate(address(lee)) - start, (block.timestamp - start) * (3000 * WAD) / (4000 * WAD));  // Deposit date updating using weighting
        assertTrue( lee.try_intendToWithdraw(address(pool)));
        assertTrue(!lee.try_withdraw(address(pool), 4000 * USD), "Withdraw failure didn't trigger");                // Not able to withdraw the funds as deposit date was updated

        uint256 interest = pool.withdrawableFundsOf(address(lee));  // Get kims withdrawable funds

        // Warp to exact time that lee can withdraw with weighted deposit date
        hevm.warp(pool.depositDate(address(lee)) + pool.lockupPeriod() - 1);
        assertTrue(!lee.try_withdraw(address(pool), 4000 * USD), "Withdraw failure didn't trigger");
        hevm.warp(pool.depositDate(address(lee)) + pool.lockupPeriod());
        assertTrue( lee.try_withdraw(address(pool), 4000 * USD), "Failed to withdraw funds");

        assertEq(IERC20(USDC).balanceOf(address(lee)) - bal0, interest);
    }

    function test_withdraw_protocol_paused() public {
        setUpWithdraw();
        
        assertTrue(pat.try_setLockupPeriod(address(pool), 0));
        assertEq(pool.lockupPeriod(), uint256(0));

        mint("USDC", address(lee), 2000 * USD);
        lee.approve(USDC, address(pool), MAX_UINT);
        assertTrue(lee.try_deposit(address(pool), 1000 * USD));
        make_withdrawable(lee, pool);

        // Protocol-wide pause by Emergency Admin
        assertTrue(!globals.protocolPaused());
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), true));

        // Attempt to withdraw while protocol paused
        assertTrue(globals.protocolPaused());
        assertTrue(!lee.try_withdrawFunds(address(pool)));
        assertTrue(!lee.try_withdraw(address(pool), 1000 * USD));

        // Unpause and withdraw
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(lee.try_withdrawFunds(address(pool)));
        assertTrue(lee.try_withdraw(address(pool), 1000 * USD));

        assertEq(IERC20(USDC).balanceOf(address(lee)), 2000 * USD);
    }

    function _makeLoanPayment(Loan _loan, Borrower by) internal {
        (uint amt,,,,) = _loan.getNextPayment();
        mint("USDC", address(by), amt);
        by.approve(USDC, address(_loan),  amt);
        by.makePayment(address(_loan));
    }

    function _drawDownLoan(uint256 drawdownAmount, Loan _loan, Borrower by) internal  {
        uint cReq =  _loan.collateralRequiredForDrawdown(drawdownAmount);
        mint("WETH", address(by), cReq);
        by.approve(WETH, address(_loan),  cReq);
        by.drawdown(address(_loan),  drawdownAmount);
    }

    function _getLLBal(Pool who) internal view returns(uint256) {
        return IERC20(USDC).balanceOf(who.liquidityLocker());
    }

    function test_deactivate() public {

        setUpWithdraw();

        address liquidityAsset = address(pool.liquidityAsset());
        uint liquidityAssetDecimals = IERC20Details(liquidityAsset).decimals();

        // Pre-state checks.
        assertTrue(pool.principalOut() <= 100 * 10 ** liquidityAssetDecimals);

        // Pause protocol and attempt deactivate()
        assertTrue( emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!pat.try_deactivate(address(pool)));

        // Unpause protocol and deactivate()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(pat.try_deactivate(address(pool)));

        // Post-state checks.
        assertEq(int(pool.poolState()), 2);

        // Deactivation should block the following functionality:

        // deposit()
        mint("USDC", address(leo), 1_000_000_000 * USD);
        leo.approve(USDC, address(pool), uint(-1));
        assertTrue(!leo.try_deposit(address(pool), 100_000_000 * USD));

        // fundLoan()
        assertTrue(!pat.try_fundLoan(address(pool), address(loan), address(dlFactory), 1));

        // deactivate()
        assertTrue(!pat.try_deactivate(address(pool)));

    }

    function test_deactivate_fail() public {

        /*******************************/
        /*** Finalize liquidity pool ***/
        /*******************************/
        {
            pat.approve(address(bPool), pool.stakeLocker(), MAX_UINT);
            pat.stake(pool.stakeLocker(), bPool.balanceOf(address(pat)) / 2);
            pat.setOpenToPublic(address(pool), true);
            pat.finalize(address(pool));
        }
        /**************************************************/
        /*** Mint and deposit funds into liquidity pool ***/
        /**************************************************/
        {
            mint("USDC", address(leo), 1_000_000_000 * USD);
            mint("USDC", address(liz), 1_000_000_000 * USD);
            mint("USDC", address(lex), 1_000_000_000 * USD);

            leo.approve(USDC, address(pool), MAX_UINT);
            liz.approve(USDC, address(pool), MAX_UINT);
            lex.approve(USDC, address(pool), MAX_UINT);

            assertTrue(leo.try_deposit(address(pool), 100_000_000 * USD));  // 10%
            assertTrue(liz.try_deposit(address(pool), 300_000_000 * USD));  // 30%
            assertTrue(lex.try_deposit(address(pool), 600_000_000 * USD));  // 60%

            gov.setValidLoanFactory(address(loanFactory), true); // Don't remove, not done in setUp()
        }

        /************************************/
        /*** Fund loan / loan2 (Excess) ***/
        /************************************/
        {
            assertTrue(pat.try_fundLoan(address(pool), address(loan),  address(dlFactory), 100_000_000 * USD));
            assertTrue(pat.try_fundLoan(address(pool), address(loan),  address(dlFactory), 100_000_000 * USD));
            assertTrue(pat.try_fundLoan(address(pool), address(loan),  address(dlFactory2), 200_000_000 * USD));
            assertTrue(pat.try_fundLoan(address(pool), address(loan),  address(dlFactory2), 200_000_000 * USD));

            assertTrue(pat.try_fundLoan(address(pool), address(loan2), address(dlFactory),  50_000_000 * USD));
            assertTrue(pat.try_fundLoan(address(pool), address(loan2), address(dlFactory),  50_000_000 * USD));
            assertTrue(pat.try_fundLoan(address(pool), address(loan2), address(dlFactory2), 150_000_000 * USD));
            assertTrue(pat.try_fundLoan(address(pool), address(loan2), address(dlFactory2), 150_000_000 * USD));
        }

        address liquidityAsset = address(pool.liquidityAsset());
        uint liquidityAssetDecimals = IERC20Details(liquidityAsset).decimals();

        // Pre-state checks.
        assertTrue(pool.principalOut() >= 100 * 10 ** liquidityAssetDecimals);
        assertTrue(!pat.try_deactivate(address(pool)));
    }

    function test_view_balance() public {
        setUpWithdraw();

        // Mint and deposit 1000 USDC
        mint("USDC", address(lee), 1_000_000 * USD);
        lee.approve(USDC, address(pool), MAX_UINT);
        assertTrue(lee.try_deposit(address(pool), 1_000_000 * USD));

        // Fund loan, drawdown, make payment and claim so lee can claim interest
        assertTrue(pat.try_fundLoan(address(pool), address(loan3),  address(dlFactory), 1_000_000 * USD), "Fail to fund the loan");
        _drawDownLoan(1_000_000 * USD, loan3, bud);
        _makeLoanPayment(loan3, bud); 
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

}
