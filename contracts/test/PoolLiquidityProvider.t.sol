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

}
