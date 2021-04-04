
// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

contract PoolLiquidationTest is TestUtil {

    using SafeMath for uint256;

    function setUp() public {
        setUpGlobals();
        setUpTokens();
        setUpOracles();
        setUpFactories();
        setUpCalcs();
        setUpActors();
        setUpBalancerPoolForPools();
        createLiquidityPools();
        stakeAndFinalizePools(10 * WAD, 25 * WAD);  // Less than 1/6 in first pool, so that all BPTs can be burned in tests
        createLoans();

        gov.setMaxSwapSlippage(2000);  // Set to 20% for the sake of the BPT shortfall test
    }

    function test_triggerDefault_pool_delegate() public {
        // Fund the pool
        mint("USDC", address(leo), 100_000_000 * USD);
        leo.approve(USDC, address(pool), MAX_UINT);
        leo.approve(USDC, address(pool2), MAX_UINT);
        leo.deposit(address(pool), 80_000_000 * USD + 1);
        leo.deposit(address(pool2), 20_000_000 * USD - 1);

        // Fund the loan
        pat.fundLoan(address(pool), address(loan), address(dlFactory), 80_000_000 * USD + 1);  // Plus 1e-6 to create exact 100m totalSupply
        pam.fundLoan(address(pool2), address(loan), address(dlFactory), 20_000_000 * USD - 1);  // 20% minus 1e-6 equity 

        // Drawdown loan
        uint cReq = loan.collateralRequiredForDrawdown(4_000_000 * USD);
        mint("WETH", address(bob), cReq);
        bob.approve(WETH, address(loan), MAX_UINT);
        bob.drawdown(address(loan), 4_000_000 * USD);  // Draw down less than total amount
        
        // Warp to late payment
        uint256 start = block.timestamp;
        uint256 nextPaymentDue = loan.nextPaymentDue();
        uint256 gracePeriod = globals.gracePeriod();
        hevm.warp(start + nextPaymentDue + gracePeriod + 1);

        // Attempt to trigger default as PD holding less than minimum LoanFDTs required (MapleGlobals.minLoanEquity)
        assertTrue(!pam.try_triggerDefault(address(pool2), address(loan), address(dlFactory)));

        // Update storage to have exactly 20% equity (totalSupply remains the same)
        hevm.store(
            address(loan),
            keccak256(abi.encode(address(pool2.debtLockers(address(loan), address(dlFactory))), 0)), // Overwrite balance to have exact 20% equity
            bytes32(uint256(20_000_000 * WAD))
        );

        // Pause protocol and attempt triggerDefault()
        assertTrue( emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!pam.try_triggerDefault(address(pool2), address(loan), address(dlFactory)));

        // Unpause protocol and triggerDefault()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(pam.try_triggerDefault(address(pool2), address(loan), address(dlFactory)));
    }

    function setUpLoanAndDefault() public {
        // Fund the pool
        mint("USDC", address(leo), 20_000_000 * USD);
        leo.approve(USDC, address(pool), MAX_UINT);
        leo.approve(USDC, address(pool2), MAX_UINT);
        leo.deposit(address(pool), 10_000_000 * USD);
        leo.deposit(address(pool2), 10_000_000 * USD);

        // Fund the loan
        pat.fundLoan(address(pool), address(loan), address(dlFactory), 1_000_000 * USD);
        pam.fundLoan(address(pool2), address(loan), address(dlFactory), 3_000_000 * USD);
        uint cReq = loan.collateralRequiredForDrawdown(4_000_000 * USD);

        // Drawdown loan
        mint("WETH", address(bob), cReq);
        bob.approve(WETH, address(loan), MAX_UINT);
        bob.drawdown(address(loan), 4_000_000 * USD);
        
        // Warp to late payment
        uint256 start = block.timestamp;
        uint256 nextPaymentDue = loan.nextPaymentDue();
        uint256 gracePeriod = globals.gracePeriod();
        hevm.warp(start + nextPaymentDue + gracePeriod + 1);

        // Trigger default
        pat.triggerDefault(address(pool), address(loan), address(dlFactory));
    }

    function test_claim_default_info() public {

        setUpLoanAndDefault();

        /**
            Now that triggerDefault() is called, the return value defaultSuffered
            will be greater than 0. Calling claim() is the mechanism which settles,
            or rather updates accounting in the Pool which in turn will enable us
            to handle liquidation of BPTs in the Stake Locker accurately.
        */
        uint256[7] memory vals_a = pat.claim(address(pool), address(loan),  address(dlFactory));
        uint256[7] memory vals_b = pam.claim(address(pool2), address(loan),  address(dlFactory));

        // Non-zero value is passed through.
        assertEq(vals_a[6], loan.defaultSuffered() * (1_000_000 * WAD) / (4_000_000 * WAD));
        assertEq(vals_b[6], loan.defaultSuffered() * (3_000_000 * WAD) / (4_000_000 * WAD));
        withinPrecision(vals_a[6] + vals_b[6], loan.defaultSuffered(), 2);

        // Call claim again to make sure that default isn't double accounted
        vals_a = pat.claim(address(pool), address(loan),  address(dlFactory));
        vals_b = pam.claim(address(pool2), address(loan),  address(dlFactory));
        assertEq(vals_a[6], 0);
        assertEq(vals_b[6], 0);
    }

    function test_claim_default_burn_BPT_full_recover() public {

        setUpLoanAndDefault();

        TestObj memory liquidityLocker_a_bal;
        TestObj memory liquidityLocker_b_bal;
        TestObj memory stakeLocker_a_bal;
        TestObj memory stakeLocker_b_bal;
        TestObj memory principalOut_a;
        TestObj memory principalOut_b;

        address liquidityLocker_a = pool.liquidityLocker();
        address liquidityLocker_b = pool2.liquidityLocker();

        // Pre-state liquidityLocker checks.
        liquidityLocker_a_bal.pre = IERC20(USDC).balanceOf(liquidityLocker_a);
        liquidityLocker_b_bal.pre = IERC20(USDC).balanceOf(liquidityLocker_b);

        stakeLocker_a_bal.pre = bPool.balanceOf(address(stakeLocker));
        stakeLocker_b_bal.pre = bPool.balanceOf(address(stakeLocker2));

        principalOut_a.pre = pool.principalOut();
        principalOut_b.pre = pool2.principalOut();

        assertEq(principalOut_a.pre, 1_000_000 * USD);
        assertEq(principalOut_b.pre, 3_000_000 * USD);

        assertEq(stakeLocker_a_bal.pre, 10 * WAD);
        assertEq(stakeLocker_b_bal.pre, 25 * WAD);

        assertEq(liquidityLocker_a_bal.pre, 9_000_000 * USD);
        assertEq(liquidityLocker_b_bal.pre, 7_000_000 * USD);

        pat.claim(address(pool), address(loan),  address(dlFactory));
        pam.claim(address(pool2), address(loan),  address(dlFactory));

        // Post-state liquidityLocker checks.
        liquidityLocker_a_bal.post = IERC20(USDC).balanceOf(liquidityLocker_a);
        liquidityLocker_b_bal.post = IERC20(USDC).balanceOf(liquidityLocker_b);

        stakeLocker_a_bal.post = bPool.balanceOf(address(stakeLocker));
        stakeLocker_b_bal.post = bPool.balanceOf(address(stakeLocker2));

        principalOut_a.post = pool.principalOut();
        principalOut_b.post = pool2.principalOut();
        
        withinDiff(liquidityLocker_a_bal.post - liquidityLocker_a_bal.pre, 1_000_000 * USD, 1);  // Entire initial loan amount was recovered between liquidation and burn
        withinDiff(liquidityLocker_b_bal.post - liquidityLocker_b_bal.pre, 3_000_000 * USD, 1);  // Entire initial loan amount was recovered between liquidation and burn

        withinDiff(principalOut_a.post, 0, 1);  // Principal out is set to zero (with dust)
        withinDiff(principalOut_b.post, 0, 1);  // Principal out is set to zero (with dust)

        assertEq(liquidityLocker_a_bal.pre  + principalOut_a.pre,  10_000_000 * USD);  // Total pool value = 9m + 1m = 10m
        assertEq(liquidityLocker_a_bal.post + principalOut_a.post, 10_000_000 * USD);  // Total pool value = 10m + 0 = 10m (successful full coverage from liquidation + staker burn)

        assertEq(liquidityLocker_b_bal.pre  + principalOut_b.pre,  10_000_000 * USD);  // Total pool value = 7m + 3m = 10m
        assertEq(liquidityLocker_b_bal.post + principalOut_b.post, 10_000_000 * USD);  // Total pool value = 1m + 0 = 10m (successful full coverage from liquidation + staker burn)

        assertTrue(stakeLocker_a_bal.pre - stakeLocker_a_bal.post > 0);  // Assert BPTs were burned
        assertTrue(stakeLocker_b_bal.pre - stakeLocker_b_bal.post > 0);  // Assert BPTs were burned

        assertEq(stakeLocker_a_bal.pre - stakeLocker_a_bal.post, stakeLocker.bptLosses());  // Assert FDT loss accounting
        assertEq(stakeLocker_a_bal.pre - stakeLocker_a_bal.post, stakeLocker.bptLosses());  // Assert FDT loss accounting
    }

    function assertPoolAccounting(Pool pool) internal {
        uint256 liquidityAssetDecimals = IERC20Details(address(pool.liquidityAsset())).decimals();

        uint256 liquidityLockerBal = pool.liquidityAsset().balanceOf(pool.liquidityLocker());
        uint256 fdtTotalSupply     = pool.totalSupply().mul(10 ** liquidityAssetDecimals).div(WAD);  // Convert to liquidityAsset precision
        uint256 principalOut       = pool.principalOut();
        uint256 interestSum        = pool.interestSum();
        uint256 poolLosses         = pool.poolLosses();

        // Total Pool Value = LLBal + PO = fdtSupply + interestSum + aggregate unrecognized losses
        assertEq(liquidityLockerBal + principalOut, fdtTotalSupply + interestSum - poolLosses, "Pool accounting compromised");
    }

    function test_claim_default_burn_BPT_shortfall() public {

        // Fund the pool
        mint("USDC", address(leo), 500_000_000 * USD);
        mint("USDC", address(liz),  10_000_000 * USD);

        leo.approve(USDC, address(pool), MAX_UINT);
        liz.approve(USDC, address(pool), MAX_UINT);
        leo.deposit(address(pool), 500_000_000 * USD);  // Ali symbolizes all other LPs, test focuses on Bob
        liz.deposit(address(pool), 10_000_000 * USD);
        assertTrue(liz.try_intendToWithdraw(address(pool)));

        assertPoolAccounting(pool);

        // Fund the loan
        pat.fundLoan(address(pool), address(loan), address(dlFactory), 100_000_000 * USD);
        uint cReq = loan.collateralRequiredForDrawdown(100_000_000 * USD);

        assertPoolAccounting(pool);

        // Drawdown loan
        mint("WETH", address(bob), cReq);
        bob.approve(WETH, address(loan), MAX_UINT);
        bob.drawdown(address(loan), 100_000_000 * USD);

        assertPoolAccounting(pool);

        // Warp to late payment
        hevm.warp(block.timestamp + loan.nextPaymentDue() + globals.gracePeriod() + 1);

        // Trigger default
        pat.triggerDefault(address(pool), address(loan), address(dlFactory));

        // Instantiate all test variables
        TestObj memory liquidityLockerBal;
        TestObj memory slBPTBal;
        TestObj memory fdtSupply;
        TestObj memory principalOut;
        TestObj memory poolLosses;
        TestObj memory bob_usdcBal;
        TestObj memory bob_poolBal;
        TestObj memory bob_recognizableLosses;

        address liquidityLocker = pool.liquidityLocker();
        address stakeLocker     = pool.stakeLocker();

        /**************************************************/
        /*** Loan Default Accounting with BPT Shortfall ***/
        /**************************************************/

        // Pre-claim accounting checks
        liquidityLockerBal.pre = IERC20(USDC).balanceOf(liquidityLocker);
        slBPTBal.pre           = bPool.balanceOf(stakeLocker);
        fdtSupply.pre          = pool.totalSupply();
        principalOut.pre       = pool.principalOut();
        poolLosses.pre         = pool.poolLosses();

        uint256[7] memory vals_a = pat.claim(address(pool), address(loan),  address(dlFactory));

        assertPoolAccounting(pool);

        // Pre-claim accounting checks
        liquidityLockerBal.post = IERC20(USDC).balanceOf(liquidityLocker);
        slBPTBal.post           = bPool.balanceOf(stakeLocker);
        fdtSupply.post          = pool.totalSupply();
        principalOut.post       = pool.principalOut();
        poolLosses.post         = pool.poolLosses();

        assertEq(principalOut.pre,       100_000_000 * USD);  // Total Pool Value (TPV) = PO + LLBal = 510m
        assertEq(liquidityLockerBal.pre, 410_000_000 * USD);

        assertEq(slBPTBal.pre,  10 * WAD);  // Assert pre-burn BPT balance
        assertLt(slBPTBal.post,     1E10);  // Dusty stakeLocker BPT return bal (less than 1e-8 WAD), meaning essentially all BPTs were burned

        assertEq(slBPTBal.pre - slBPTBal.post, IStakeLocker(stakeLocker).bptLosses());  // Assert FDT loss accounting

        assertEq(poolLosses.pre,                 0);  // No poolLosses before bpt burning occurs
        assertGt(poolLosses.post, 40_000_000 * USD);  // Over $40m in shortfall after liquidation and BPT burn

        assertEq(fdtSupply.pre,  510_000_000 * WAD);  // TPV = fdtSupply + interestSum - shortfall = PO + LLBal
        assertEq(fdtSupply.post, 510_000_000 * WAD);  // TPV = 510m + 0 - 0

        assertEq(liquidityLockerBal.pre  + principalOut.pre,                    510_000_000 * USD);  // TPV = LLBal + PO + shortfall = 510m (shortfall = aggregate unrecognizedLosses of LPs)
        assertEq(liquidityLockerBal.post + principalOut.post + poolLosses.post, 510_000_000 * USD);  // LLBal + PO goes down, poolLosses distributes that loss - TPV = LL + PO + SF stays constant

        withinDiff(principalOut.post, 0, 1);  // Principal out is set to zero after claim has been made (with dust)

        /********************************************************/
        /*** Liquidity Provider Minimum Withdrawal Accounting ***/
        /********************************************************/

        make_withdrawable(liz, pool);

        bob_recognizableLosses.pre = pool.recognizableLossesOf(address(liz));  // Unrealized losses of liz from shortfall

        assertTrue(!liz.try_withdraw(address(pool), bob_recognizableLosses.pre - 1));  // Cannot withdraw less than recognizableLosses

        bob_usdcBal.pre = IERC20(USDC).balanceOf(address(liz));  // Bob USDC bal
        bob_poolBal.pre = pool.balanceOf(address(liz));        // Bob FDT  bal

        // Withdraw lowest possible amount (amt == recognizableLosses)
        // NOTE: LPs can withdraw more than this amount, it will just go towards their USDC
        assertTrue(!liz.try_transfer(address(pool), address(leo), bob_poolBal.pre));
        assertTrue( liz.try_withdraw(address(pool), bob_recognizableLosses.pre));

        assertPoolAccounting(pool);

        bob_recognizableLosses.post = pool.recognizableLossesOf(address(liz));  // Unrealized losses of liz after withdrawal

        bob_usdcBal.post = IERC20(USDC).balanceOf(address(liz));  // Bob USDC bal
        bob_poolBal.post = pool.balanceOf(address(liz));        // Bob FDT  bal

        liquidityLockerBal.pre  = liquidityLockerBal.post;                  // Update pre/post variables for withdrawal checks
        liquidityLockerBal.post = IERC20(USDC).balanceOf(liquidityLocker);  // Update pre/post variables for withdrawal checks

        fdtSupply.pre  = fdtSupply.post;        // Update pre/post variables for withdrawal checks
        fdtSupply.post = pool.totalSupply();  // Update pre/post variables for withdrawal checks

        poolLosses.pre  = poolLosses.post;      // Update pre/post variables for withdrawal checks
        poolLosses.post = pool.poolLosses();  // Update pre/post variables for withdrawal checks

        assertEq(bob_recognizableLosses.post, 0);  // After withdrawal, liz has zero unrecognized losses

        assertEq(bob_usdcBal.pre,  0);  // Deposited entire balance into pool
        assertEq(bob_usdcBal.post, 0);  // Withdrew enough just to realize losses, no USDC was transferred out of LL

        assertEq(bob_usdcBal.post - bob_usdcBal.pre,  0);                                       // Bob's USDC value withdrawn did not increase
        assertEq(bob_poolBal.pre  - bob_poolBal.post, bob_recognizableLosses.pre * WAD / 1E6);  // Bob's FDTs have been burned (doing assertion in WAD precision)
        assertEq(fdtSupply.pre    - fdtSupply.post,   bob_recognizableLosses.pre * WAD / 1E6);  // Bob's FDTs have been burned (doing assertion in WAD precision)
        assertEq(poolLosses.pre   - poolLosses.post,  bob_recognizableLosses.pre);              // BPT shortfall accounting has been decremented by Bob's recognized losses 

        assertEq(liquidityLockerBal.pre - liquidityLockerBal.post, 0);  // No USDC was transferred out of LL

        /**********************************************************/
        /*** Liquidity Provider Post-Loss Withdrawal Accounting ***/
        /**********************************************************/

        bob_usdcBal.pre = bob_usdcBal.post;  // Bob USDC bal
        bob_poolBal.pre = bob_poolBal.post;  // Bob FDT  bal

        uint256 withdrawAmt = bob_poolBal.pre * 1E6 / WAD;

        make_withdrawable(liz, pool);

        assertTrue(liz.try_withdraw(address(pool), withdrawAmt));  // Withdraw max amount

        assertPoolAccounting(pool);

        bob_usdcBal.post = IERC20(USDC).balanceOf(address(liz));  // Bob USDC bal
        bob_poolBal.post = pool.balanceOf(address(liz));        // Bob FDT  bal

        liquidityLockerBal.pre  = liquidityLockerBal.post;                  // Update pre/post variables for withdrawal checks
        liquidityLockerBal.post = IERC20(USDC).balanceOf(liquidityLocker);  // Update pre/post variables for withdrawal checks

        fdtSupply.pre  = fdtSupply.post;        // Update pre/post variables for withdrawal checks
        fdtSupply.post = pool.totalSupply();  // Update pre/post variables for withdrawal checks

        assertEq(bob_usdcBal.pre,  0);            // Deposited entire balance into pool
        assertEq(bob_usdcBal.post, withdrawAmt);  // Withdrew enough just to realize losses, no USDC was transferred out of LL

        assertEq(bob_poolBal.post, 0);  // Withdrew entire amount, so all remaining BPTs are burned

        assertEq(fdtSupply.pre - fdtSupply.post, bob_poolBal.pre); // Bob's FDTs have been burned

        assertEq(liquidityLockerBal.pre - liquidityLockerBal.post, withdrawAmt);  // All Bob's USDC was transferred out of LL
    }

    function make_withdrawable(LP investor, Pool pool) public {
        uint256 currentTime = block.timestamp;
        assertTrue(investor.try_intendToWithdraw(address(pool)));
        assertEq(pool.withdrawCooldown(address(investor)), currentTime, "Incorrect value set");
        hevm.warp(currentTime + globals.lpCooldownPeriod());
    }
} 
