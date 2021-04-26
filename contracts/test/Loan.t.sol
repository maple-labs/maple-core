// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

contract LoanTest is TestUtil {

    function setUp() public {
        setUpGlobals();
        setUpTokens();
        setUpOracles();
        setUpFactories();
        setUpCalcs();
        setUpActors();
        setUpBalancerPool();
        setUpLiquidityPool();
        createLoan();
    }

    function assertLoanState(
        Loan loan,
        uint256 loanState,
        uint256 principalOwed,
        uint256 principalPaid,
        uint256 interestPaid,
        uint256 loanBalance,
        uint256 paymentsRemaining,
        uint256 nextPaymentDue
    )
        internal
    {
        assertEq(uint256(loan.loanState()),             loanState);
        assertEq(loan.principalOwed(),              principalOwed);
        assertEq(loan.principalPaid(),              principalPaid);
        assertEq(loan.interestPaid(),                interestPaid);
        assertEq(usdc.balanceOf(address(loan)),       loanBalance);
        assertEq(loan.paymentsRemaining(),      paymentsRemaining);
        assertEq(loan.nextPaymentDue(),            nextPaymentDue);
    }

    function drawdown(Loan loan, uint256 drawdownAmount) internal returns (uint256 reqCollateral) {
        reqCollateral = loan.collateralRequiredForDrawdown(drawdownAmount);
        mint("WETH", address(bob), reqCollateral);
        bob.approve(WETH, address(loan), reqCollateral);
        assertTrue(bob.try_drawdown(address(loan), drawdownAmount));  // Borrow draws down on loan
    }

    function test_createLoan(
        uint256 apr,
        uint256 index,
        uint256 numPayments,
        uint256 requestAmount,
        uint256 collateralRatio
    )
        public
    {
        uint256[5] memory specs = getFuzzedSpecs(apr, index, numPayments, requestAmount, collateralRatio);
        address[3] memory calcs = [address(repaymentCalc), address(lateFeeCalc), address(premiumCalc)];

        Loan loan = bob.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);

        assertEq(address(loan.liquidityAsset()),   USDC);
        assertEq(address(loan.collateralAsset()),  WETH);
        assertEq(loan.flFactory(),                 address(flFactory));
        assertEq(loan.clFactory(),                 address(clFactory));
        assertEq(loan.borrower(),                  address(bob));
        assertEq(loan.createdAt(),                 block.timestamp);
        assertEq(loan.apr(),                       specs[0]);
        assertEq(loan.termDays(),                  specs[1]);
        assertEq(loan.paymentsRemaining(),         specs[1] / specs[2]);
        assertEq(loan.paymentIntervalSeconds(),    specs[2] * 1 days);
        assertEq(loan.requestAmount(),             specs[3]);
        assertEq(loan.collateralRatio(),           specs[4]);
        assertEq(loan.fundingPeriod(),             globals.fundingPeriod());
        assertEq(loan.defaultGracePeriod(),        globals.defaultGracePeriod());
        assertEq(loan.repaymentCalc(),             address(repaymentCalc));
        assertEq(loan.lateFeeCalc(),               address(lateFeeCalc));
        assertEq(loan.premiumCalc(),               address(premiumCalc));
    }

    function test_fundLoan(
        uint256 apr,
        uint256 index,
        uint256 numPayments,
        uint256 requestAmount,
        uint256 collateralRatio,
        uint256 fundAmount,
        uint256 fundAmount2
    )
        public
    {
        uint256[5] memory specs = getFuzzedSpecs(apr, index, numPayments, requestAmount, collateralRatio);
        address[3] memory calcs = [address(repaymentCalc), address(lateFeeCalc), address(premiumCalc)];

        Loan loan = bob.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);

        address fundingLocker   = loan.fundingLocker();
        address liquidityLocker = pool.liquidityLocker();

        fundAmount = constrictToRange(fundAmount, 1 * USD, 1E10 * USD);
        uint256 wadAmount = fundAmount * WAD / USD;

        fundAmount2 = constrictToRange(fundAmount, 1 * USD, 1E10 * USD);
        uint256 wadAmount2 = fundAmount2 * WAD / USD;

        mint("USDC", address(leo),       (fundAmount + fundAmount2));
        leo.approve(USDC, address(pool), (fundAmount + fundAmount2));
        leo.deposit(address(pool),       (fundAmount + fundAmount2));

        // Note: Cannot do pre-state check for LoanFDT balance of debtLocker since it is not instantiated
        assertEq(usdc.balanceOf(address(fundingLocker)),                            0);
        assertEq(usdc.balanceOf(address(liquidityLocker)), (fundAmount + fundAmount2));

        // Loan-specific pause by Borrower
        assertTrue(!loan.paused());
        assertTrue(!cam.try_pause(address(loan)));
        assertTrue( bob.try_pause(address(loan)));
        assertTrue(loan.paused());
        assertTrue(!pat.try_fundLoan(address(pool), address(loan), address(dlFactory), fundAmount));  // Allow for two fundings

        assertTrue(!cam.try_unpause(address(loan)));
        assertTrue( bob.try_unpause(address(loan)));
        assertTrue(!loan.paused());

        uint256 start = block.timestamp;

        hevm.warp(start + globals.fundingPeriod() + 1);  // Warp to past fundingPeriod, loan cannot be funded
        assertTrue(!pat.try_fundLoan(address(pool), address(loan), address(dlFactory), fundAmount));

        hevm.warp(start + globals.fundingPeriod());  // Warp to fundingPeriod, loan can be funded
        assertTrue(pat.try_fundLoan(address(pool), address(loan), address(dlFactory), fundAmount));

        address debtLocker = pool.debtLockers(address(loan), address(dlFactory));

        assertEq(loan.balanceOf(address(debtLocker)),        wadAmount);
        assertEq(usdc.balanceOf(address(fundingLocker)),    fundAmount);
        assertEq(usdc.balanceOf(address(liquidityLocker)), fundAmount2);

        // Protocol-wide pause by Emergency Admin
        assertTrue(!cam.try_setProtocolPause(address(globals), true));
        assertTrue( emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(globals.protocolPaused());
        assertTrue(!pat.try_fundLoan(address(pool), address(loan), address(dlFactory), fundAmount2));

        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(!globals.protocolPaused());
        assertTrue(pat.try_fundLoan(address(pool), address(loan), address(dlFactory), fundAmount2));

        assertEq(loan.balanceOf(address(debtLocker)),        wadAmount + wadAmount2);
        assertEq(usdc.balanceOf(address(fundingLocker)),   fundAmount + fundAmount2);
        assertEq(usdc.balanceOf(address(liquidityLocker)),                        0);
    }

    function createAndFundLoan(
        uint256 apr,
        uint256 index,
        uint256 numPayments,
        uint256 requestAmount,
        uint256 collateralRatio,
        uint256 fundAmount
    )
        internal returns (Loan loan)
    {
        uint256[5] memory specs = getFuzzedSpecs(apr, index, numPayments, requestAmount, collateralRatio);
        address[3] memory calcs = [address(repaymentCalc), address(lateFeeCalc), address(premiumCalc)];

        loan = bob.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);

        fundAmount = constrictToRange(fundAmount, specs[3], 1E10 * USD, true);  // Fund between requestAmount and 10b USD
        uint256 wadAmount = fundAmount * WAD / USD;

        mint("USDC", address(leo),       fundAmount);
        leo.approve(USDC, address(pool), fundAmount);
        leo.deposit(address(pool),       fundAmount);

        pat.fundLoan(address(pool), address(loan), address(dlFactory), fundAmount);
    }

    function test_collateralRequiredForDrawdown(
        uint256 apr,
        uint256 index,
        uint256 numPayments,
        uint256 requestAmount,
        uint256 collateralRatio,
        uint256 fundAmount,
        uint256 drawdownAmount
    )
        public
    {
        Loan loan = createAndFundLoan(apr, index, numPayments, requestAmount, collateralRatio, fundAmount);

        address fundingLocker = loan.fundingLocker();

        drawdownAmount = constrictToRange(drawdownAmount, 1 * USD, usdc.balanceOf(fundingLocker));
        uint256 collateralValue = drawdownAmount * loan.collateralRatio() / 10_000;

        uint256 reqCollateral = loan.collateralRequiredForDrawdown(drawdownAmount);
        withinDiff(reqCollateral * globals.getLatestPrice(WETH) * USD / WAD / 10 ** 8, collateralValue, 1);
    }

    function test_drawdown(
        uint256 apr,
        uint256 index,
        uint256 numPayments,
        uint256 requestAmount,
        uint256 collateralRatio,
        uint256 fundAmount,
        uint256 drawdownAmount
    )
        public
    {
        Loan loan = createAndFundLoan(apr, index, numPayments, requestAmount, collateralRatio, fundAmount);
        address fundingLocker = loan.fundingLocker();
        fundAmount = usdc.balanceOf(fundingLocker);

        drawdownAmount = constrictToRange(drawdownAmount, loan.requestAmount(), fundAmount, true);

        assertTrue(!ben.try_drawdown(address(loan), drawdownAmount));                                  // Non-borrower can't drawdown
        if (loan.collateralRatio() > 0) assertTrue(!bob.try_drawdown(address(loan), drawdownAmount));  // Can't drawdown without approving collateral

        uint256 reqCollateral = loan.collateralRequiredForDrawdown(drawdownAmount);
        mint("WETH", address(bob),       reqCollateral);
        bob.approve(WETH, address(loan), reqCollateral);

        assertTrue(!bob.try_drawdown(address(loan), loan.requestAmount() - 1));  // Can't drawdown less than requestAmount
        assertTrue(!bob.try_drawdown(address(loan),           fundAmount + 1));  // Can't drawdown more than fundingLocker balance

        uint pre = usdc.balanceOf(address(bob));

        assertEq(weth.balanceOf(address(bob)),  reqCollateral);  // Borrower collateral balance
        assertEq(usdc.balanceOf(fundingLocker),    fundAmount);  // Funding locker liquidityAsset balance
        assertEq(usdc.balanceOf(address(loan)),             0);  // Loan liquidityAsset balance
        assertEq(loan.principalOwed(),                      0);  // Principal owed
        assertEq(uint256(loan.loanState()),                 0);  // Loan state: Ready

        // Fee related variables pre-check.
        assertEq(loan.feePaid(),                            0);  // feePaid amount
        assertEq(loan.excessReturned(),                     0);  // excessReturned amount
        assertEq(usdc.balanceOf(address(treasury)),         0);  // Treasury liquidityAsset balance

        // Pause protocol and attempt drawdown()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!bob.try_drawdown(address(loan), drawdownAmount));

        // Unpause protocol and drawdown()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(bob.try_drawdown(address(loan), drawdownAmount));

        assertEq(weth.balanceOf(address(bob)),                                 0);  // Borrower collateral balance
        assertEq(weth.balanceOf(address(loan.collateralLocker())), reqCollateral);  // Collateral locker collateral balance

        uint256 investorFee = drawdownAmount * globals.investorFee() / 10_000;
        uint256 treasuryFee = drawdownAmount * globals.treasuryFee() / 10_000;

        assertEq(usdc.balanceOf(fundingLocker),                                         0);  // Funding locker liquidityAsset balance
        assertEq(usdc.balanceOf(address(loan)), fundAmount - drawdownAmount + investorFee);  // Loan liquidityAsset balance
        assertEq(loan.principalOwed(),                                     drawdownAmount);  // Principal owed
        assertEq(uint256(loan.loanState()),                                             1);  // Loan state: Active

        withinDiff(usdc.balanceOf(address(bob)), drawdownAmount - (investorFee + treasuryFee), 1); // Borrower liqudityAsset balance

        assertEq(loan.nextPaymentDue(), block.timestamp + loan.paymentIntervalSeconds());  // Next payment due timestamp calculated from time of drawdown

        // Fee related variables post-check.
        assertEq(loan.feePaid(),                                    investorFee);  // Drawdown amount
        assertEq(loan.excessReturned(),             fundAmount - drawdownAmount);  // Principal owed
        assertEq(usdc.balanceOf(address(treasury)),                 treasuryFee);  // Treasury loanAsset balance

        // Test FDT accounting
        address debtLocker = pool.debtLockers(address(loan), address(dlFactory));
        assertEq(loan.balanceOf(debtLocker), fundAmount * WAD / USD);
        withinDiff(loan.withdrawableFundsOf(address(debtLocker)), fundAmount - drawdownAmount + investorFee, 1);

        // Can't drawdown() loan after it has already been called.
        assertTrue(!bob.try_drawdown(address(loan), drawdownAmount));
    }

    function test_makePayment(
        uint256 apr,
        uint256 index,
        uint256 numPayments,
        uint256 requestAmount,
        uint256 collateralRatio,
        uint256 fundAmount,
        uint256 drawdownAmount
    )
        public
    {
        Loan loan = createAndFundLoan(apr, index, numPayments, requestAmount, collateralRatio, fundAmount);  // Const three payments used for this test
        address fundingLocker = loan.fundingLocker();
        fundAmount = usdc.balanceOf(fundingLocker);

        drawdownAmount = constrictToRange(drawdownAmount, loan.requestAmount(), fundAmount, true);

        assertEq(uint256(loan.loanState()), 0);  // Loan state: Ready

        assertTrue(!bob.try_makePayment(address(loan)));  // Can't makePayment when State != Active

        // Approve collateral and drawdown loan.
        uint256 reqCollateral = drawdown(loan, drawdownAmount);
        uint256 loanPreBal    = usdc.balanceOf(address(loan));  // Accounts for excess and fees from drawdown

        // NOTE: Do not need to hevm.warp in this test because payments can be made whenever as long as they are before the nextPaymentDue

        uint256 numPayments = loan.paymentsRemaining();
        // Approve 1st of 3 payments.
        (uint total, uint principal, uint interest, uint due,) = loan.getNextPayment();
        if(total == 0 && interest == 0) return;  // If fuzz params cause payments to be so small they round to zero, skip fuzz iteration

        assertTrue(!bob.try_makePayment(address(loan)));  // Can't makePayment with lack of approval

        mint("USDC", address(bob),       total);
        bob.approve(USDC, address(loan), total);

        // Before state
        assertLoanState({
            loan:              loan,
            loanState:         1,
            principalOwed:     drawdownAmount,
            principalPaid:     0,
            interestPaid:      0,
            loanBalance:       loanPreBal,
            paymentsRemaining: numPayments,
            nextPaymentDue:    due
        });

        // Pause protocol and attempt makePayment()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!bob.try_makePayment(address(loan)));

        // Unpause protocol and makePayment()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(bob.try_makePayment(address(loan)));  // Make payment.

        due += loan.paymentIntervalSeconds();  // Increment next payment due by interval

        // After state
        assertLoanState({
            loan:              loan,
            loanState:         1,
            principalOwed:     drawdownAmount,
            principalPaid:     0,
            interestPaid:      interest,
            loanBalance:       loanPreBal + interest,
            paymentsRemaining: numPayments - 1,
            nextPaymentDue:    due
        });

        // Approve numPayments - 1.
        for (uint256 i = 2; i <= numPayments - 1; i++) {
            repetitivePayment(loan, numPayments, i, drawdownAmount, loanPreBal, uint256(0));
        }
        
        // Approve last payment.
        (total, principal, interest, due,) = loan.getNextPayment();
        mint("USDC", address(bob),       total);
        bob.approve(USDC, address(loan), total);

        // Check collateral locker balance.
        assertEq(weth.balanceOf(loan.collateralLocker()), reqCollateral);

        // Make last payment.
        assertTrue(bob.try_makePayment(address(loan)));

        due += loan.paymentIntervalSeconds();  // Increment next payment due by interval

        // After state, state variables.
        assertLoanState({
            loan:              loan,
            loanState:         2,
            principalOwed:     0,
            principalPaid:     principal,
            interestPaid:      interest * numPayments,
            loanBalance:       loanPreBal + interest * numPayments + principal,
            paymentsRemaining: 0,
            nextPaymentDue:    0
        });

        // Collateral locker after state.
        assertEq(weth.balanceOf(loan.collateralLocker()),             0);
        assertEq(weth.balanceOf(address(bob)),            reqCollateral);
    }

    function test_makePayment_late(
        uint256 apr,
        uint256 index,
        uint256 numPayments,
        uint256 requestAmount,
        uint256 collateralRatio,
        uint256 fundAmount,
        uint256 drawdownAmount
    )
        public
    {
        Loan loan = createAndFundLoan(apr, index, numPayments, requestAmount, collateralRatio, fundAmount);  // Const three payments used for this test
        address fundingLocker = loan.fundingLocker();
        fundAmount = usdc.balanceOf(fundingLocker);

        drawdownAmount = constrictToRange(drawdownAmount, loan.requestAmount(), fundAmount, true);

        assertEq(uint256(loan.loanState()), 0);  // Loan state: Ready

        assertTrue(!bob.try_makePayment(address(loan)));  // Can't makePayment when State != Active

        // Approve collateral and drawdown loan.
        uint256 reqCollateral = drawdown(loan, drawdownAmount);
        uint256 loanPreBal    = usdc.balanceOf(address(loan));  // Accounts for excess and fees from drawdown
        uint256 numPayments   = loan.paymentsRemaining();

        // Approve 1st of 3 payments.
        (uint256 total, uint256 principal, uint256 interest, uint256 due,) = loan.getNextPayment();
        if(total == 0 && interest == 0) return;  // If fuzz params cause payments to be so small they round to zero, skip fuzz iteration

        assertTrue(!bob.try_makePayment(address(loan)));  // Can't makePayment with lack of approval

        mint("USDC", address(bob),       total);
        bob.approve(USDC, address(loan), total);

        // Before state
        assertLoanState({
            loan:              loan,
            loanState:         1,
            principalOwed:     drawdownAmount,
            principalPaid:     0,
            interestPaid:      0,
            loanBalance:       loanPreBal,
            paymentsRemaining: numPayments,
            nextPaymentDue:    due
        });

        // Make first payment on time.
        assertTrue(bob.try_makePayment(address(loan)));

        due += loan.paymentIntervalSeconds();  // Increment next payment due by interval

        // After state
        assertLoanState({
            loan:              loan,
            loanState:         1,
            principalOwed:     drawdownAmount,
            principalPaid:     0,
            interestPaid:      interest,
            loanBalance:       loanPreBal + interest,
            paymentsRemaining: numPayments - 1,
            nextPaymentDue:    due
        });

        // Approve numPayments - 1.
        for (uint256 i = 1; i < numPayments - 1; i++) {
            // Warp to 1 second after next payment is due (payment is late)
            hevm.warp(loan.nextPaymentDue() + 1);
            repetitivePayment(loan, numPayments, i, drawdownAmount, loanPreBal, interest);
        }

        uint256 interest_late;

        // Warp to 1 second after next payment is due (payment is late)
        hevm.warp(loan.nextPaymentDue() + 1);

        // Approve 3nd of 3 payments.
        (total, principal, interest_late, due,) = loan.getNextPayment();
        mint("USDC", address(bob),       total);
        bob.approve(USDC, address(loan), total);

        // Check collateral locker balance.
        assertEq(weth.balanceOf(loan.collateralLocker()), reqCollateral);

        // Make payment.
        assertTrue(bob.try_makePayment(address(loan)));

        due += loan.paymentIntervalSeconds();  // Increment next payment due by interval

        // After state, state variables.
        assertLoanState({
            loan:              loan,
            loanState:         2,
            principalOwed:     0,
            principalPaid:     principal,
            interestPaid:      interest + interest_late * (numPayments - 1),
            loanBalance:       loanPreBal + interest + interest_late * (numPayments - 1) + principal,
            paymentsRemaining: 0,
            nextPaymentDue:    0
        });

        // Collateral locker after state.
        assertEq(weth.balanceOf(loan.collateralLocker()),             0);
        assertEq(weth.balanceOf(address(bob)),            reqCollateral);
    }

    function test_unwind_loan(
        uint256 apr,
        uint256 index,
        uint256 numPayments,
        uint256 requestAmount,
        uint256 collateralRatio,
        uint256 fundAmount,
        uint256 drawdownAmount
    )
        public
    {

        TestObj memory flBalance;
        TestObj memory loanBalance;
        TestObj memory loanState;

        Loan loan = createAndFundLoan(apr, index, numPayments, requestAmount, collateralRatio, fundAmount);  // Const three payments used for this test
        address fundingLocker = loan.fundingLocker();
        fundAmount = usdc.balanceOf(fundingLocker);

        // Warp to the fundingPeriod, can't call unwind() yet
        hevm.warp(loan.createdAt() + globals.fundingPeriod());
        assertTrue(!pat.try_unwind(address(loan)));

        flBalance.pre   = usdc.balanceOf(fundingLocker);
        loanBalance.pre = usdc.balanceOf(address(loan));
        loanState.pre   = uint256(loan.loanState());

        // Warp 1 more second, can call unwind()
        hevm.warp(loan.createdAt() + globals.fundingPeriod() + 1);

        // Pause protocol and attempt unwind()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!pat.try_unwind(address(loan)));

        // Unpause protocol and unwind()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(pat.try_unwind(address(loan)));

        flBalance.post   = usdc.balanceOf(fundingLocker);
        loanBalance.post = usdc.balanceOf(address(loan));
        loanState.post   = uint256(loan.loanState());

        assertEq(loanBalance.pre, 0);
        assertEq(loanState.pre,   0);

        assertEq(flBalance.post, 0);
        assertEq(loanState.post, 3);

        assertEq(flBalance.pre,    fundAmount);
        assertEq(loanBalance.post, fundAmount);

        assertEq(loan.excessReturned(), loanBalance.post);

        // Pause protocol and attempt withdrawFunds() (through claim)
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!pat.try_claim(address(pool), address(loan), address(dlFactory)));

        // Unpause protocol and withdrawFunds() (through claim)
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(pat.try_claim(address(pool), address(loan), address(dlFactory)));

        withinDiff(usdc.balanceOf(address(pool.liquidityLocker())), fundAmount, 1);
        withinDiff(usdc.balanceOf(address(loan)),                            0, 1);

        // Can't unwind() loan after it has already been called.
        assertTrue(!pat.try_unwind(address(loan)));
    }

    function test_trigger_default(
        uint256 apr,
        uint256 index,
        uint256 numPayments,
        uint256 requestAmount,
        uint256 collateralRatio,
        uint256 fundAmount,
        uint256 drawdownAmount
    )
        public
    {
        gov.setMaxSwapSlippage(10_000);  // Set 100% slippage to account for very large liquidations from fuzzing

        Loan loan = createAndFundLoan(apr, index, numPayments, requestAmount, collateralRatio, fundAmount);
        address fundingLocker = loan.fundingLocker();
        fundAmount = IERC20(USDC).balanceOf(fundingLocker);
        uint256 wadAmount = fundAmount * WAD / USD;

        drawdownAmount = constrictToRange(drawdownAmount, loan.requestAmount(), fundAmount, true);

        address debtLocker = pool.debtLockers(address(loan), address(dlFactory));

        assertEq(uint256(loan.loanState()), 0);  // `Ready` state

        uint256 reqCollateral = drawdown(loan, drawdownAmount);

        assertEq(uint256(loan.loanState()), 1);  // `Active` state

        assertTrue(!pat.try_triggerDefault(address(pool), address(loan), address(dlFactory)));  // Should fail to trigger default because current time is still less than the `nextPaymentDue`.
        assertTrue(!cam.try_triggerDefault(address(loan)));                                     // Failed because commoner in not allowed to default the loan because they do not own any LoanFDTs.

        hevm.warp(loan.nextPaymentDue() + 1);

        assertTrue(!pat.try_triggerDefault(address(pool), address(loan), address(dlFactory)));  // Failed because still loan has defaultGracePeriod to repay the dues.
        assertTrue(!cam.try_triggerDefault(address(loan)));                                     // Failed because still commoner is not allowed to default the loan.

        hevm.warp(loan.nextPaymentDue() + globals.defaultGracePeriod());

        assertTrue(!pat.try_triggerDefault(address(pool), address(loan), address(dlFactory)));  // Failed because still loan has defaultGracePeriod to repay the dues.
        assertTrue(!cam.try_triggerDefault(address(loan)));                                     // Failed because still commoner is not allowed to default the loan.

        hevm.warp(loan.nextPaymentDue() + globals.defaultGracePeriod() + 1);

        assertTrue(!cam.try_triggerDefault(address(loan)));  // Failed because still commoner is not allowed to default the loan.

        // Sid's Pool currently has 100% of LoanFDTs, so he can trigger the loan default.
        // For this test, minLoanEquity is transferred to the commoner to test the minimum loan equity condition.
        assertEq(loan.totalSupply(),       wadAmount);
        assertEq(globals.minLoanEquity(),       2000);  // 20%

        uint256 minEquity = loan.totalSupply() * globals.minLoanEquity() / 10_000;

        // Simulate transfer of LoanFDTs from DebtLocker to commoner (<20% of total supply)
        hevm.store(
            address(loan),
            keccak256(abi.encode(address(cam), 0)), // Mint tokens
            bytes32(uint256(minEquity - 1))
        );
        hevm.store(
            address(loan),
            keccak256(abi.encode(address(debtLocker), 0)), // Overwrite balance
            bytes32(uint256(wadAmount - minEquity + 1))
        );

        assertTrue(!cam.try_triggerDefault(address(loan)));  // Failed because still commoner is not allowed to default the loan.

        // "Transfer" 1 more wei to meet 20% minimum equity requirement
        hevm.store(
            address(loan),
            keccak256(abi.encode(address(cam), 0)), // Mint tokens
            bytes32(uint256(minEquity))
        );
        hevm.store(
            address(loan),
            keccak256(abi.encode(address(debtLocker), 0)), // Overwrite balance
            bytes32(uint256(wadAmount - minEquity))
        );

        assertTrue(cam.try_triggerDefault(address(loan)));  // Now with 20% of loan equity, a loan can be defaulted
        assertEq(uint256(loan.loanState()), 4);
    }

    function test_calc_min_amount(
        uint256 apr,
        uint256 index,
        uint256 requestAmount,
        uint256 collateralRatio,
        uint256 fundAmount,
        uint256 drawdownAmount
    )
        public
    {
        Loan loan = createAndFundLoan(apr, index, 3, requestAmount, collateralRatio, fundAmount);  // Const three payments used for this test
        address fundingLocker = loan.fundingLocker();
        fundAmount = IERC20(USDC).balanceOf(fundingLocker);

        drawdownAmount = constrictToRange(drawdownAmount, loan.requestAmount(), fundAmount, true);

        uint256 reqCollateral = drawdown(loan, drawdownAmount);

        uint256 expectedAmount = (reqCollateral * globals.getLatestPrice(WETH)) / globals.getLatestPrice(USDC);

        assertEq((expectedAmount * USD) / WAD, loan.getExpectedAmountRecovered());
    }

    function test_makeFullPayment(
        uint256 apr,
        uint256 index,
        uint256 numPayments,
        uint256 requestAmount,
        uint256 collateralRatio,
        uint256 fundAmount,
        uint256 drawdownAmount
    )
        public
    {
        Loan loan = createAndFundLoan(apr, index, numPayments, requestAmount, collateralRatio, fundAmount);
        fundAmount = usdc.balanceOf(loan.fundingLocker());

        drawdownAmount = constrictToRange(drawdownAmount, loan.requestAmount(), fundAmount, true);

        assertEq(uint256(loan.loanState()), 0);  // Loan state: Ready

        assertTrue(!bob.try_makeFullPayment(address(loan)));  // Can't makePayment when State != Active

        // Approve collateral and drawdown loan.
        uint256 reqCollateral = drawdown(loan, drawdownAmount);
        uint256 loanPreBal    = usdc.balanceOf(address(loan));

        assertTrue(!bob.try_makeFullPayment(address(loan)));  // Can't makePayment with lack of approval

        // Approve full payment.
        (uint total, uint principal, uint interest) = loan.getFullPayment();
        mint("USDC", address(bob), total);
        bob.approve(USDC, address(loan), total);

        // Before state
        assertLoanState({
            loan:              loan,
            loanState:         1,
            principalOwed:     drawdownAmount,
            principalPaid:     0,
            interestPaid:      0,
            loanBalance:       loanPreBal,
            paymentsRemaining: loan.paymentsRemaining(),
            nextPaymentDue:    block.timestamp + loan.paymentIntervalSeconds()  // Not relevant to full payment
        });

        // Collateral locker before state.
        assertEq(weth.balanceOf(loan.collateralLocker()), reqCollateral);
        assertEq(weth.balanceOf(address(bob)),                 0);

        // Pause protocol and attempt makeFullPayment()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!bob.try_makeFullPayment(address(loan)));

        // Unpause protocol and makeFullPayment()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(bob.try_makeFullPayment(address(loan)));  // Make full payment.

        // After state
        assertEq(usdc.balanceOf(address(loan)), loanPreBal + total);

        assertLoanState({
            loan:              loan,
            loanState:         2,
            principalOwed:     0,
            principalPaid:     principal,
            interestPaid:      interest,
            loanBalance:       loanPreBal + interest + principal,
            paymentsRemaining: 0,
            nextPaymentDue:    0
        });

        // Collateral locker after state.
        assertEq(weth.balanceOf(loan.collateralLocker()),             0);
        assertEq(weth.balanceOf(address(bob)),     reqCollateral);
    }

    function test_reclaim_erc20() external {
        // Add different kinds of assets to the loan.
        mint("USDC", address(loan), 1000 * USD);
        mint("DAI",  address(loan), 1000 * WAD);
        mint("WETH", address(loan),  100 * WAD);

        Governor fakeGov = new Governor();

        uint256 beforeBalanceDAI  =  dai.balanceOf(address(gov));
        uint256 beforeBalanceWETH = weth.balanceOf(address(gov));

        assertTrue(!fakeGov.try_reclaimERC20(address(loan), DAI));
        assertTrue(    !gov.try_reclaimERC20(address(loan), USDC));  // Governor cannot remove liquidityAsset from loans
        assertTrue(    !gov.try_reclaimERC20(address(loan), address(0)));
        assertTrue(     gov.try_reclaimERC20(address(loan), WETH));
        assertTrue(     gov.try_reclaimERC20(address(loan), DAI));

        uint256 afterBalanceDAI  =  dai.balanceOf(address(gov));
        uint256 afterBalanceWETH = weth.balanceOf(address(gov));

        assertEq(afterBalanceDAI  - beforeBalanceDAI,  1000 * WAD);
        assertEq(afterBalanceWETH - beforeBalanceWETH,  100 * WAD);
    }

    function test_setLoanAdmin() public {
        // Pause protocol and attempt setLoanAdmin()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!bob.try_setLoanAdmin(address(loan), address(securityAdmin), true));
        assertTrue(!loan.loanAdmins(address(securityAdmin)));

        // Unpause protocol and setLoanAdmin()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(bob.try_setLoanAdmin(address(loan), address(securityAdmin), true));
        assertTrue(loan.loanAdmins(address(securityAdmin)));
    }

    function repetitivePayment(Loan loan, uint256 numPayments, uint256 paymentCount, uint256 drawdownAmount, uint256 loanPreBal, uint256 oldInterest) internal {
        (uint256 total,, uint256 interest, uint256 due,) = loan.getNextPayment();
        mint("USDC", address(bob),       total);
        bob.approve(USDC, address(loan), total);

        // Below is the way of catering two senarios
        // 1. When there is no late payment so interest paid will be a multiple of `numPayments`.
        // 2. If there is a late payment then needs to handle the situation where interst paid is `interest (without late fee) + interest (late fee) * numPayments`.
        numPayments = oldInterest == uint256(0) ? numPayments - paymentCount : numPayments - paymentCount - 1;
        // Make payment.
        assertTrue(bob.try_makePayment(address(loan)));

        due += loan.paymentIntervalSeconds();  // Increment next payment due by interval

        // After state
        assertLoanState({
            loan:              loan,
            loanState:         1,
            principalOwed:     drawdownAmount,
            principalPaid:     0,
            interestPaid:      oldInterest + (interest * paymentCount),
            loanBalance:       loanPreBal  + oldInterest + (interest * paymentCount),
            paymentsRemaining: numPayments,
            nextPaymentDue:    due
        });
    }
}
