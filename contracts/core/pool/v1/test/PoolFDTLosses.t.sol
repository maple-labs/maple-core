// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "test/TestUtil.sol";

contract PoolFDTLossesTest is TestUtil {

    using SafeMath for uint256;

    function setUp() public {
        setUpGlobals();
        setUpTokens();
        setUpOracles();
        setUpFactories();
        setUpCalcs();
        setUpActors();
        setUpBalancerPool();
        setUpLiquidityPools();
        createLoans();
    }

    function createLoanForLossesAndGetDepositAmount(
        uint256 apr,
        uint256 index,
        uint256 numPayments,
        uint256 requestAmount,
        uint256 collateralRatio,
        uint256 minimumRequestAmt
    ) internal returns (Loan custom_loan, uint256 depositAmt) {
        uint256[5] memory specs = getFuzzedSpecs(apr, index, numPayments, requestAmount, collateralRatio, (125 * minimumRequestAmt) / 100, 0, 1E7 * USD);
        address[3] memory calcs = [address(repaymentCalc), address(lateFeeCalc), address(premiumCalc)];

        custom_loan = bob.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);
        depositAmt  = constrictToRange(requestAmount, specs[3], 1E7 * USD, true);
    }

    function getClaimedInterestNetOfFees(uint256 interestPortionClaimed, uint256 delegateFee, uint256 stakingFee) internal pure returns (uint256 claimedInterest) {
        uint256 fees    = interestPortionClaimed.mul(delegateFee).div(10_000);
        fees            = fees.add(interestPortionClaimed.mul(stakingFee).div(10_000));
        claimedInterest = interestPortionClaimed.sub(fees);
    }

    function getSplitDepositAmounts(uint256 amount, uint256 totalAmount) internal pure returns (uint256 amount1, uint256 amount2) {
        amount1 = constrictToRange(amount, totalAmount / 1000, totalAmount, true);
        amount2 = totalAmount - amount1;
    }

    function test_lpBearingLosses(
        uint256 apr,
        uint256 index,
        uint256 numPayments,
        uint256 requestAmount
    ) public {
        uint256 minimumRequestAmt = PoolLib.getSwapOutValueLocker(address(bPool), USDC, address(pool1.stakeLocker()));

        // Create Loan with 0% CR, so no claimable funds are present after default, and a deposit amount from arguments
        (Loan custom_loan, uint256 depositAmt) = createLoanForLossesAndGetDepositAmount(apr, index, numPayments, requestAmount, 0, minimumRequestAmt);

        // Lex is putting up the funds into the Pool.
        mintFundsAndDepositIntoPool(leo, pool1, depositAmt, depositAmt);

        // Fund the loan by the pool delegate.
        pat.fundLoan(address(pool1), address(custom_loan), address(dlFactory1), depositAmt);

        // Drawdown of the loan.
        drawdown(custom_loan, bob, depositAmt);

        // Time warp to make a payment.
        hevm.warp(custom_loan.nextPaymentDue());
        doPartialLoanPayment(custom_loan, bob);

        // Claim the funds.
        uint256[7] memory claimInfo = pat.claim(address(pool1), address(custom_loan), address(dlFactory1));

        // Leo withdraws interest.
        leo.withdrawFunds(address(pool1));

        // Verify the interest.
        withinDiff(
            getClaimedInterestNetOfFees(claimInfo[1], pool1.delegateFee(), pool1.stakingFee()),
            usdc.balanceOf(address(leo)),
            1
        );

        // Time warp to default
        hevm.warp(custom_loan.nextPaymentDue() + globals.defaultGracePeriod() + 1);

        // Setting slippage high enough to let it through the liquidations.
        gov.setMaxSwapSlippage(7000);

        // Pool Delegate trigger a default
        pat.triggerDefault(address(pool1), address(custom_loan), address(dlFactory1));

        // Check for successful default.
        assertTrue(uint8(custom_loan.loanState()) == 4, "Unexpected Loan state");

        // PD claims funds and also sells the stake to recover the losses.
        claimInfo = pat.claim(address(pool1), address(custom_loan), address(dlFactory1));

        assertTrue(claimInfo[6] > 0, "Loan doesn't have default suffered");

        uint256 poolLosses = pool1.poolLosses();
        assertTrue(poolLosses > 0, "Pool losses should be greater than 0");
        withinDiff(pool1.recognizableLossesOf(address(leo)), poolLosses, 1);

        // Time warp to past lockup to remove lockup transfer restriction
        hevm.warp(block.timestamp + pool1.lockupPeriod() + 1);

        // Fails to transfer if the losses are > 0.
        assertTrue(
            !leo.try_transfer(address(pool1), address(leo), 1),
            "Should not be allowed to transfer because losses are > 0"
        );

        // Intend to withdraw and warp to withdraw window
        leo.intendToWithdraw(address(pool1));
        hevm.warp(block.timestamp + globals.lpCooldownPeriod() + 1);

        // Before withdrawing funds.
        uint256 old_lex_bal = usdc.balanceOf(address(leo));

        // Withdrawing half should be sufficient to recognize all the losses
        leo.withdraw(address(pool1), depositAmt - 1);

        withinDiff(usdc.balanceOf(address(leo)) - old_lex_bal, depositAmt - poolLosses - 1, 1);

        assertTrue(
            leo.try_transfer(address(pool1), address(liz), 1 * (WAD / USD)),
            "Should be allowed to transfer because losses recognized"
        );

        assertEq(pool1.balanceOf(address(liz)), 1 * (WAD / USD), "Liz should have 1 FDT");
    }

    function test_multipleLpBearingLossesWithMultiplePools(
        uint256 apr,
        uint256 index,
        uint256 numPayments,
        uint256 requestAmount,
        uint256 leoDepositAmt,
        uint256 lexDepositAmt
    ) public {
        uint256 minDepositAmountForPool1 = PoolLib.getSwapOutValueLocker(address(bPool), USDC, address(pool1.stakeLocker()));
        uint256 minDepositAmountForPool2 = PoolLib.getSwapOutValueLocker(address(bPool), USDC, address(pool2.stakeLocker()));

        // Create Loan and a deposit amount from arguments
        (Loan custom_loan, uint256 totalDepositAmt) = createLoanForLossesAndGetDepositAmount(apr, index, numPayments, requestAmount, 0, minDepositAmountForPool1 + minDepositAmountForPool2);

        uint256 lizDepositAmt;
        (leoDepositAmt, lizDepositAmt) = getSplitDepositAmounts(leoDepositAmt, (minDepositAmountForPool1 * totalDepositAmt) / (minDepositAmountForPool1 + minDepositAmountForPool2));

        uint256 leeDepositAmt;
        (lexDepositAmt, leeDepositAmt) = getSplitDepositAmounts(lexDepositAmt, totalDepositAmt - leoDepositAmt - lizDepositAmt);

        // LPs is putting up the funds into the Pool.
        mintFundsAndDepositIntoPool(leo, pool1,  leoDepositAmt, leoDepositAmt);
        mintFundsAndDepositIntoPool(liz, pool1,  lizDepositAmt, lizDepositAmt);
        mintFundsAndDepositIntoPool(lex, pool2, lexDepositAmt, lexDepositAmt);
        mintFundsAndDepositIntoPool(lee, pool2, leeDepositAmt, leeDepositAmt);

        // Fund the loan by both pool delegates.
        pat.fundLoan(address(pool1), address(custom_loan), address(dlFactory1), usdc.balanceOf(pool1.liquidityLocker()));
        pam.fundLoan(address(pool2), address(custom_loan), address(dlFactory1), usdc.balanceOf(pool2.liquidityLocker()));

        // Drawdown of the loan
        drawdown(custom_loan, bob, totalDepositAmt);

        // Time warp to make a payment
        hevm.warp(custom_loan.nextPaymentDue());
        doPartialLoanPayment(custom_loan, bob);

        {
            // Claim the funds.
            uint256[7] memory claimInfo1 = pat.claim(address(pool1), address(custom_loan), address(dlFactory1));
            uint256[7] memory claimInfo2 = pam.claim(address(pool2), address(custom_loan), address(dlFactory1));

            // Withdraw interest by the lps.
            leo.withdrawFunds(address(pool1));
            liz.withdrawFunds(address(pool1));
            lex.withdrawFunds(address(pool2));
            lee.withdrawFunds(address(pool2));

            // Verify the interest.
            withinDiff(
                getClaimedInterestNetOfFees(claimInfo1[1], pool1.delegateFee(), pool1.stakingFee()),
                usdc.balanceOf(address(leo)) + usdc.balanceOf(address(liz)),
                1
            );

            withinDiff(
                getClaimedInterestNetOfFees(claimInfo2[1], pool2.delegateFee(), pool2.stakingFee()),
                usdc.balanceOf(address(lex)) + usdc.balanceOf(address(lee)),
                1
            );

            // Time warp to default
            hevm.warp(custom_loan.nextPaymentDue() + globals.defaultGracePeriod() + 1);

            // Setting slippage high enough to let it through the liquidations.
            gov.setMaxSwapSlippage(7000);

            // At least one of the pool delegates should be able to trigger a default
            assertTrue(
                pat.try_triggerDefault(address(pool1), address(custom_loan), address(dlFactory1)) ||
                pam.try_triggerDefault(address(pool2), address(custom_loan), address(dlFactory1)),
                "Should be able to trigger Loan default"
            );

            // Check for successful default.
            assertTrue(uint8(custom_loan.loanState()) == 4, "Unexpected Loan state");

            claimInfo1 = pat.claim(address(pool1), address(custom_loan), address(dlFactory1));
            claimInfo2 = pam.claim(address(pool2), address(custom_loan), address(dlFactory1));

            assertTrue(claimInfo1[6]     > 0,      "Loan doesn't have default suffered");
            assertTrue(pool1.poolLosses() > 0, "Pool 1 losses should be greater than 0");
            withinDiff(pool1.recognizableLossesOf(address(leo)) + pool1.recognizableLossesOf(address(liz)), pool1.poolLosses(), 1);

            assertTrue(claimInfo2[6]      > 0,     "Loan doesn't have default suffered");
            assertTrue(pool2.poolLosses() > 0, "Pool 2 losses should be greater than 0");
            withinDiff(pool2.recognizableLossesOf(address(lex)) + pool2.recognizableLossesOf(address(lee)), pool2.poolLosses(), 1);
        }

        // Time warp to past lockup to remove lockup transfer restriction
        hevm.warp(block.timestamp + pool1.lockupPeriod() + 1);

        // Fails to transfer if the losses are > 0.
        assertTrue(
            !leo.try_transfer(address(pool1), address(liz), 1),
            "Should not allow Lex to transfer because losses are > 0"
        );

        assertTrue(
            !liz.try_transfer(address(pool1), address(leo), 1),
            "Should not allow Lee to transfer because losses are > 0"
        );

        assertTrue(
            !lex.try_transfer(address(pool2), address(lee), 1),
            "Should not allow Leo to transfer because losses are > 0"
        );

        assertTrue(
            !lee.try_transfer(address(pool2), address(lex), 1),
            "Should not allow Liz to transfer because losses are > 0"
        );

        // LPs is withdrawing funds from the Pool with losses.
        leo.intendToWithdraw(address(pool1));
        liz.intendToWithdraw(address(pool1));
        lex.intendToWithdraw(address(pool2));
        lee.intendToWithdraw(address(pool2));

        // Time warp to withdraw window
        hevm.warp(block.timestamp + globals.lpCooldownPeriod() + 1);

        // Before withdrawing funds.
        uint256 old_leo_bal = usdc.balanceOf(address(leo));
        uint256 old_liz_bal = usdc.balanceOf(address(liz));
        uint256 old_lex_bal = usdc.balanceOf(address(lex));
        uint256 old_lee_bal = usdc.balanceOf(address(lee));

        leo.withdraw(address(pool1), leoDepositAmt - 1);
        liz.withdraw(address(pool1), lizDepositAmt - 1);
        lex.withdraw(address(pool2), lexDepositAmt - 1);
        lee.withdraw(address(pool2), leeDepositAmt - 1);

        assertEq(pool1.balanceOf(address(leo)), 1 * (WAD / USD), "Leo should have 1 FDTs");
        assertEq(pool1.balanceOf(address(liz)), 1 * (WAD / USD), "Liz should have 1 FDTs");
        assertEq(pool2.balanceOf(address(lex)), 1 * (WAD / USD), "Lex should have 1 FDTs");
        assertEq(pool2.balanceOf(address(lex)), 1 * (WAD / USD), "Lee should have 1 FDTs");

        withinDiff(usdc.balanceOf(address(leo)) - old_leo_bal, leoDepositAmt - pool1.recognizedLossesOf(address(leo)) - 1,  1);
        withinDiff(usdc.balanceOf(address(liz)) - old_liz_bal, lizDepositAmt - pool1.recognizedLossesOf(address(liz)) - 1,  1);
        withinDiff(usdc.balanceOf(address(lex)) - old_lex_bal, lexDepositAmt - pool2.recognizedLossesOf(address(lex)) - 1, 1);
        withinDiff(usdc.balanceOf(address(lee)) - old_lee_bal, leeDepositAmt - pool2.recognizedLossesOf(address(lee)) - 1, 1);

        // Leo transfers 1 Pool1 FDT to Lex (who is not in a Pool1 withdrawal window)
        assertTrue(
            leo.try_transfer(address(pool1), address(lex), 1 * (WAD / USD)),
            "Should allow Leo to transfer because losses recognized"
        );

        // Lex transfers 1 Pool2 FDT to Leo (who is not in a Pool2 withdrawal window)
        assertTrue(
            lex.try_transfer(address(pool2), address(leo), 1 * (WAD / USD)),
            "Should allow Lex to transfer because losses recognized"
        );

        assertEq(pool1.balanceOf(address(lex)), 1 * (WAD / USD), "Lex should have 1 Pool1 FDTs");
        assertEq(pool2.balanceOf(address(leo)), 1 * (WAD / USD), "Leo should have 1 Pool2 FDTs");

        // Lez transfers 1 Pool1 FDT to Lee (who is not in a Pool1 withdrawal window)
        assertTrue(
            liz.try_transfer(address(pool1), address(lee), 1 * (WAD / USD)),
            "Should allow Liz to transfer because losses recognized"
        );

        // Lee transfers 1 Pool2 FDT to Liz (who is not in a Pool2 withdrawal window)
        assertTrue(
            lee.try_transfer(address(pool2), address(liz), 1 * (WAD / USD)),
            "Should allow Lee to transfer because losses recognized"
        );

        assertEq(pool1.balanceOf(address(lee)), 1 * (WAD / USD), "Lee should have 1 Pool1 FDTs");
        assertEq(pool2.balanceOf(address(liz)), 1 * (WAD / USD), "Liz should have 1 Pool2 FDTs");
    }

}
