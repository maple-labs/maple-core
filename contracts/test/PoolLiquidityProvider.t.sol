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

    function test_deposit(uint256 depositAmt) public {
        address stakeLocker = pool.stakeLocker();
        address liqLocker   = pool.liquidityLocker();

        depositAmt = constrictToRange(depositAmt, 1 * USD, 100 * USD, true);

        assertTrue(!leo.try_deposit(address(pool), depositAmt)); // Not finalized

        finalizePool(pool, pat, false);

        // Mint 100 USDC into this LP account
        mint("USDC", address(leo), depositAmt);

        assertTrue(!pool.openToPublic());
        assertTrue(!pool.allowedLiquidityProviders(address(leo)));
        assertTrue( !leo.try_deposit(address(pool), depositAmt)); // Not in the LP allow list neither the pool is open to public.

        assertTrue( !pam.try_setAllowList(address(pool), address(leo), true)); // It will fail as `pam` is not the right PD.
        assertTrue(  pat.try_setAllowList(address(pool), address(leo), true));
        assertTrue( pool.allowedLiquidityProviders(address(leo)));
        
        assertTrue(!leo.try_deposit(address(pool), depositAmt)); // Not Approved

        leo.approve(USDC, address(pool), MAX_UINT);

        assertLiquidity(pool, leo, liqLocker, depositAmt, 0, 0);

        assertTrue(leo.try_deposit(address(pool), depositAmt));

        assertLiquidity(pool, leo, liqLocker, 0, depositAmt, toWad(depositAmt));

        // Remove leo from the allowed list
        assertTrue(pat.try_setAllowList(address(pool), address(leo), false));
        mint("USDC", address(leo), depositAmt);
        assertTrue(!leo.try_deposit(address(pool), depositAmt));

        uint256 newDepositAmt = constrictToRange(depositAmt, 100 * USD, 200 * USD, true);

        mint("USDC", address(lex), newDepositAmt);
        lex.approve(USDC, address(pool), MAX_UINT);
        
        assertLiquidity(pool, lex, liqLocker, newDepositAmt, depositAmt, 0);

        assertTrue(!pool.allowedLiquidityProviders(address(lex)));
        assertTrue(  !lex.try_deposit(address(pool), 100 * USD)); // Fail to invest as lex is not in the allowed list.

        // Pause protocol and attempt openPoolToPublic()
        assertTrue( emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!pat.try_setOpenToPublic(address(pool), true));

        // Unpause protocol and openPoolToPublic()
        assertTrue( emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(!pam.try_setOpenToPublic(address(pool), true));  // Incorrect PD.
        assertTrue( pat.try_setOpenToPublic(address(pool), true));

        assertTrue(lex.try_deposit(address(pool), 100 * USD));

        assertLiquidity(pool, lex, liqLocker, newDepositAmt - 100 * USD, depositAmt + 100 * USD, toWad(100 * USD));

        mint("USDC", address(leo), depositAmt);

        // Pool-specific pause by Pool Delegate via setLiquidityCap(0)
        assertEq(  pool.liquidityCap(), MAX_UINT);
        assertTrue(!cam.try_setLiquidityCap(address(pool), 0));
        assertTrue( pat.try_setLiquidityCap(address(pool), 0));
        assertEq(  pool.liquidityCap(), 0);
        assertTrue(!leo.try_deposit(address(pool), 1 * USD));
        assertTrue( pat.try_setLiquidityCap(address(pool), MAX_UINT));
        assertEq(  pool.liquidityCap(), MAX_UINT);
        assertTrue( leo.try_deposit(address(pool), depositAmt));
        assertEq(  pool.balanceOf(address(leo)), toWad(2 * depositAmt));
 
        // Protocol-wide pause by Emergency Admin
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!leo.try_deposit(address(pool), 1 * USD));
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(leo.try_deposit(address(pool), depositAmt));
        assertEq( pool.balanceOf(address(leo)), toWad(3 * depositAmt));

        // Pause protocol and attempt setLiquidityCap()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!pat.try_setLiquidityCap(address(pool), MAX_UINT));

        // Unpause protocol and setLiquidityCap()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(pat.try_setLiquidityCap(address(pool), MAX_UINT));

        assertTrue( pat.try_setOpenToPublic(address(pool),      false));  // Close pool to public
        assertTrue(!lex.try_deposit(address(pool),         depositAmt));  // Fail to deposit as pool no longer public
    }

    function test_deposit_with_liquidity_cap(uint256 newLiquidityCap) public {

        finalizePool(pool, pat, true);

        // Mint 10_000 USDC into this LP account
        mint("USDC", address(leo), 10_000 * USD);
        leo.approve(USDC, address(pool), MAX_UINT);

        newLiquidityCap = constrictToRange(newLiquidityCap, 10 * USD, 1000 * USD, true);

        // Changes the `liquidityCap`.
        assertTrue(pat.try_setLiquidityCap(address(pool), newLiquidityCap), "Failed to set liquidity cap");
        assertEq( pool.liquidityCap(), newLiquidityCap,                     "Incorrect value set for liquidity cap");

        // Not able to deposit as cap is lower than the deposit amount.
        assertTrue(!pool.isDepositAllowed(newLiquidityCap + 1),                "Deposit should not be allowed because liquidityCap < depositAmt");
        assertTrue( !leo.try_deposit(address(pool), newLiquidityCap + 1),      "Should not able to deposit depositAmt");

        // Tries with lower amount it will pass.
        assertTrue(pool.isDepositAllowed(newLiquidityCap - 1),                  "Deposit should be allowed because liquidityCap > depositAmt");
        assertTrue( leo.try_deposit(address(pool), newLiquidityCap - 1),        "Fail to deposit depositAmt");

        // leo tried again with 6 USDC it fails again.
        assertTrue(!pool.isDepositAllowed(2),                         "Deposit should not be allowed because liquidityCap < newLiquidityCap - 1 + 2");
        assertTrue( !leo.try_deposit(address(pool), 2),               "Should not able to deposit 2 USD");

        // Set liquidityCap to zero and withdraw
        assertTrue(pat.try_setLiquidityCap(address(pool), 0),         "Failed to set liquidity cap");
        assertTrue(pat.try_setLockupPeriod(address(pool), 0),         "Failed to set the lockup period");
        assertEq( pool.lockupPeriod(), uint256(0),                    "Failed to update the lockup period");

        assertTrue(leo.try_intendToWithdraw(address(pool)),           "Failed to intend to withdraw");

        hevm.warp(block.timestamp + globals.lpCooldownPeriod() + 1);
        assertTrue(leo.try_withdraw(address(pool), 1 * USD),        "Should pass to withdraw the funds from the pool");
    }

    function test_deposit_depositDate(uint256 depositAmt) public {
       
        finalizePool(pool, pat, true);
        
        // Mint 100 USDC into this LP account
        uint256 startDate  = block.timestamp;
        uint256 depositAmt = constrictToRange(depositAmt, 100 * USD, 10_000_000 * USD, true);
        mintFundsAndDepositIntoPool(leo, pool, 20_000_000 * USD, depositAmt);
    
        assertEq(pool.depositDate(address(leo)), startDate);

        uint256 newAmt = constrictToRange(depositAmt, 1 * USD, 100_000 * USD, true);

        hevm.warp(startDate + 30 days);
        leo.deposit(address(pool), newAmt);

        uint256 newDepDate = startDate + (block.timestamp - startDate) * newAmt / (newAmt + depositAmt);
        assertEq(pool.depositDate(address(leo)), newDepDate);  // Gets updated

        assertTrue(pat.try_setLockupPeriod(address(pool), uint256(0)));  // Sets 0 as lockup period to allow withdraw. 
        make_withdrawable(leo, pool);
        leo.withdraw(address(pool), newAmt);

        assertEq(pool.depositDate(address(leo)), newDepDate);  // Doesn't change
    }

    function test_transfer_lockup_period(uint256 depositAmt) public {
        finalizePool(pool, pat, true);

        // Deposit 100 USDC on first day
        uint256 startDate = block.timestamp;
        uint256 depositAmt = constrictToRange(depositAmt, 100 * USD, 10_000_000 * USD, true);

        // Mint 200 USDC into this LP account
        mintFundsAndDepositIntoPool(leo, pool, 20_000_000 * USD, depositAmt);
        mintFundsAndDepositIntoPool(liz, pool, 20_000_000 * USD, depositAmt);

        assertEq(pool.depositDate(address(leo)), startDate);
        assertEq(pool.depositDate(address(liz)), startDate);
        assertEq(pool.balanceOf(address(leo)), toWad(depositAmt));
        assertEq(pool.balanceOf(address(liz)), toWad(depositAmt));

        uint256 newDeposit = constrictToRange(depositAmt, 50 * USD, depositAmt, true);  // Amount of FDT transferred

        // Will fail because lockup period hasn't passed yet
        assertTrue(!liz.try_transfer(address(pool), address(leo), toWad(newDeposit)));

        // Warp to just before lockup period ends
        hevm.warp(startDate + pool.lockupPeriod() - 1);
        assertTrue(!liz.try_transfer(address(pool), address(leo), toWad(newDeposit)));

        // Warp to after lockup period
        hevm.warp(startDate + pool.lockupPeriod());

        // Pause protocol and attempt to transfer FDTs
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!liz.try_transfer(address(pool), address(leo), toWad(newDeposit)));

        // Unpause protocol and transfer FDTs
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(liz.try_transfer(address(pool), address(leo), toWad(newDeposit)));  // Pool.transfer()

        // Check balances and deposit dates are correct
        assertEq(pool.balanceOf(address(leo)), toWad(depositAmt) + toWad(newDeposit));
        assertEq(pool.balanceOf(address(liz)), toWad(depositAmt) - toWad(newDeposit));
        uint256 newDepDate = startDate + (block.timestamp - startDate) * toWad(newDeposit) / (toWad(newDeposit) + toWad(depositAmt));
        assertEq(pool.depositDate(address(leo)), newDepDate);  // Gets updated
        assertEq(pool.depositDate(address(liz)), startDate);   // Stays the same
    }

    function test_transfer_recipient_withdrawing(uint256 depositAmt) public {
        finalizePool(pool, pat, true);
        pat.setLockupPeriod(address(pool), 0);

        // Deposit 100 USDC on first day
        uint256 start = block.timestamp;
        depositAmt    = constrictToRange(depositAmt, 100 * USD, 10_000_000 * USD, true);

        // Mint 200 USDC into this LP account
        mintFundsAndDepositIntoPool(leo, pool, 10_000_000 * USD, depositAmt);
        mintFundsAndDepositIntoPool(liz, pool, 10_000_000 * USD, depositAmt);

        assertEq(pool.balanceOf(address(leo)), toWad(depositAmt));
        assertEq(pool.balanceOf(address(liz)), toWad(depositAmt));
        assertEq(pool.depositDate(address(leo)), start);
        assertEq(pool.depositDate(address(liz)), start);

        // LP (Liz) initiates withdrawal
        assertTrue(liz.try_intendToWithdraw(address(pool)), "Failed to intend to withdraw");
        assertEq( pool.withdrawCooldown(address(liz)), start);

        // LP (Leo) fails to transfer to LP (liz) that is currently withdrawing
        assertTrue(!leo.try_transfer(address(pool), address(liz), toWad(depositAmt)));
        hevm.warp(start + globals.lpCooldownPeriod() + globals.lpWithdrawWindow());  // Very end of LP withdrawal window
        assertTrue(!leo.try_transfer(address(pool), address(liz), toWad(depositAmt)));

        // LP (leo) successfully transfers to LP (liz) that is outside withdraw window
        hevm.warp(start + globals.lpCooldownPeriod() + globals.lpWithdrawWindow() + 1);  // Second after LP withdrawal window ends
        assertTrue( leo.try_transfer(address(pool), address(liz), toWad(depositAmt)));
        assertTrue(!liz.try_withdraw(address(pool), toWad(depositAmt)));

        // Check balances and deposit dates are correct
        assertEq(pool.balanceOf(address(leo)), 0);
        assertEq(pool.balanceOf(address(liz)), toWad(depositAmt) * 2);
        uint256 newDepDate = start + (block.timestamp - start) * (toWad(depositAmt)) / ((toWad(depositAmt)) + (toWad(depositAmt)));
        assertEq(pool.depositDate(address(leo)), start);       // Stays the same
        assertEq(pool.depositDate(address(liz)), newDepDate);  // Gets updated
    }

    function test_withdraw_cooldown(uint256 depositAmt) public {

        gov.setLpCooldownPeriod(10 days);

        finalizePool(pool, pat, true);
        pat.setLockupPeriod(address(pool), 0);

        depositAmt = constrictToRange(depositAmt, 100 * USD, 10_000_000 * USD, true);

        // Mint 1000 USDC into this LP account
        mintFundsAndDepositIntoPool(leo, pool, 10_000_000 * USD, depositAmt);

        uint256 amt   = depositAmt / 3; // 1/3 of deposit so withdraw can happen thrice
        uint256 start = block.timestamp;

        assertTrue(!leo.try_withdraw(address(pool), amt),     "Should fail to withdraw 500 USD because account has to intendToWithdraw");
        assertTrue(!lex.try_intendToWithdraw(address(pool)),  "Should fail to intend to withdraw because lex has zero pool FDTs");
        assertTrue( leo.try_intendToWithdraw(address(pool)),  "Should fail to intend to withdraw");
        assertEq(  pool.withdrawCooldown(address(leo)), start);
        assertTrue(!leo.try_withdraw(address(pool), amt),      "Should fail to withdraw as cooldown period hasn't passed yet");

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
        
        // ** Below is the test of resetting feature of withdrawCooldown after withdrawing funds again and again ** //

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

        finalizePool(pool, pat, true);

        // Mint USDC to lee and deposit into Pool
        mintFundsAndDepositIntoPool(lee, pool, 1000 * USD, 1000 * USD);

        assertEq(pool.withdrawCooldown(address(lee)), 0);
        assertTrue(lee.try_intendToWithdraw(address(pool)));
        assertEq(pool.withdrawCooldown(address(lee)), block.timestamp);

        assertTrue(lee.try_cancelWithdraw(address(pool)));
        assertEq(pool.withdrawCooldown(address(lee)), 0);
    }

    function test_withdraw_under_lockup_period(uint256 depositAmt) public {
        finalizePool(pool, pat, true);
        gov.setValidLoanFactory(address(loanFactory), true);

        // Ignore cooldown for this test
        gov.setLpWithdrawWindow(MAX_UINT);

        uint256 start = block.timestamp;
        depositAmt    = constrictToRange(depositAmt, 1000 * USD, 10_000_000 * USD, true);
        // Mint USDC to lee
        mintFundsAndDepositIntoPool(lee, pool, 10_000_000 * USD, depositAmt);
        uint256 bal0 = 10_000_000 * USD;
        
        // Check depositDate
        assertEq(pool.depositDate(address(lee)), start);

        // Fund loan, drawdown, make payment and claim so lee can claim interest
        assertTrue(pat.try_fundLoan(address(pool), address(loan3),  address(dlFactory), depositAmt), "Fail to fund the loan");
        drawdown(loan3, bud, depositAmt);
        doFullLoanPayment(loan3, bud); 
        pat.claim(address(pool), address(loan3), address(dlFactory));

        uint256 interest = pool.withdrawableFundsOf(address(lee));  // Get kim's withdrawable funds

        assertTrue(lee.try_intendToWithdraw(address(pool)));
        // Warp to exact time that lee can withdraw with weighted deposit date
        hevm.warp( pool.depositDate(address(lee)) + pool.lockupPeriod() - 1);
        assertTrue(!lee.try_withdraw(address(pool), depositAmt), "Withdraw failure didn't trigger");
        hevm.warp( pool.depositDate(address(lee)) + pool.lockupPeriod());
        assertEq(pool.balanceOf(address(lee)), toWad(depositAmt));
        assertTrue( lee.try_withdraw(address(pool), depositAmt), "Failed to withdraw funds");

        assertEq(IERC20(USDC).balanceOf(address(lee)) - bal0, interest);
    }

    function test_withdraw_under_weighted_lockup_period(uint256 depositAmt) public {
        finalizePool(pool, pat, true);
        gov.setValidLoanFactory(address(loanFactory), true);

        // Ignore cooldown for this test
        gov.setLpWithdrawWindow(MAX_UINT);

        uint256 start = block.timestamp;
        depositAmt    = constrictToRange(depositAmt, 1000 * USD, 10_000_000 * USD, true);

        // Mint USDC to lee
        mintFundsAndDepositIntoPool(lee, pool, 20_000_000 * USD, depositAmt);
        uint256 bal0 = 20_000_000 * USD;

        // Check depositDate
        assertEq(pool.depositDate(address(lee)), start);

        // Fund loan, drawdown, make payment and claim so lee can claim interest
        assertTrue(pat.try_fundLoan(address(pool), address(loan3),  address(dlFactory), depositAmt), "Fail to fund the loan");
        drawdown(loan3, bud, depositAmt);
        doFullLoanPayment(loan3, bud); 
        pat.claim(address(pool), address(loan3), address(dlFactory));

        // Warp to exact time that lee can withdraw for the first time
        hevm.warp(start + pool.lockupPeriod());  
        assertEq(block.timestamp - pool.depositDate(address(lee)), pool.lockupPeriod());  // Can withdraw at this point
        
        // Deposit more USDC into pool, increasing deposit date and locking up funds again
        uint256 newDepositAmt = constrictToRange(depositAmt, 1000 * USD, 10_000_000 * USD, true);
        assertTrue(lee.try_deposit(address(pool), newDepositAmt));
        assertEq( pool.depositDate(address(lee)) - start, (block.timestamp - start) * (toWad(newDepositAmt)) / (toWad(newDepositAmt) + toWad(depositAmt)));  // Deposit date updating using weighting
        assertTrue( lee.try_intendToWithdraw(address(pool)));
        assertTrue(!lee.try_withdraw(address(pool), newDepositAmt + depositAmt), "Withdraw failure didn't trigger");                // Not able to withdraw the funds as deposit date was updated

        uint256 interest = pool.withdrawableFundsOf(address(lee));  // Get kim's withdrawable funds

        // Warp to exact time that lee can withdraw with weighted deposit date
        assertTrue(!lee.try_withdraw(address(pool), newDepositAmt + depositAmt), "Withdraw failure didn't trigger");
        hevm.warp(pool.depositDate(address(lee)) + pool.lockupPeriod());
        assertTrue( lee.try_withdraw(address(pool), newDepositAmt + depositAmt), "Failed to withdraw funds");

        assertEq(IERC20(USDC).balanceOf(address(lee)) - bal0, interest);
    }

    function test_withdraw_protocol_paused() public {
        finalizePool(pool, pat, true);
        gov.setValidLoanFactory(address(loanFactory), true);
        
        assertTrue(pat.try_setLockupPeriod(address(pool), 0));
        assertEq(pool.lockupPeriod(), uint256(0));

        mintFundsAndDepositIntoPool(lee, pool, 2000 * USD, 1000 * USD);
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

    /***************/
    /*** Helpers ***/
    /***************/

    function assertLiquidity(Pool pool, LP lp, address liqLocker, uint256 balanceOfLp, uint256 balanceOfLiqLocker, uint256 balanceOfPoolFdt) internal {
        assertEq(IERC20(USDC).balanceOf(address(lp)), balanceOfLp);
        assertEq(IERC20(USDC).balanceOf(liqLocker),   balanceOfLiqLocker);
        assertEq(pool.balanceOf(address(lp)),         balanceOfPoolFdt);
    }

}
