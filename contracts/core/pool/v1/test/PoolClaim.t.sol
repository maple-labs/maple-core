// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import { SafeMath } from "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { IDebtLocker } from "core/debt-locker/v1/interfaces/IDebtLocker.sol";
import { IDebtLockerFactory } from "core/debt-locker/v1/interfaces/IDebtLockerFactory.sol";
import { ILoan } from "core/loan/v1/interfaces/ILoan.sol";
import { IPool } from "core/pool/v1/interfaces/IPool.sol";

import { Loan } from "core/loan/v1/Loan.sol";

import { PremiumCalc } from "core/premium-calculator/v1/PremiumCalc.sol";

import { TestUtil } from "test/TestUtil.sol";
import { PoolDelegate } from "test/user/PoolDelegate.sol";

contract PoolClaimTest is TestUtil {

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

    function test_claim_permissions() public {
        // Add liquidity into the pool (lex is an LP, but still won't be able to claim)
        mintFundsAndDepositIntoPool(lex, pool1, 10_000 * USD, 10_000 * USD);

        // Fund Loan (so that debtLocker is instantiated and given LoanFDTs)
        assertTrue(pat.try_fundLoan(address(pool1), address(loan1), address(dlFactory1), 10_000 * USD));

        // Assert that LPs and non-admins cannot claim
        assertTrue(!lex.try_claim(address(pool1), address(loan1), address(dlFactory1)));            // Does not have permission to call `claim()` function
        assertTrue(!securityAdmin.try_claim(address(pool1), address(loan1), address(dlFactory1)));  // Does not have permission to call `claim()` function

        // Pool delegate can claim
        assertTrue(pat.try_claim(address(pool1), address(loan1), address(dlFactory1)));   // Successfully call the `claim()` function

        // Admin can claim once added
        pat.setPoolAdmin(address(pool1), address(securityAdmin), true);                            // Add admin to allow to call the `claim()` function
        assertTrue(securityAdmin.try_claim(address(pool1), address(loan1), address(dlFactory1)));  // Successfully call the `claim()` function

        // Pause protocol and attempt claim()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!securityAdmin.try_claim(address(pool1), address(loan1), address(dlFactory1)));

        // Unpause protocol and claim()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(securityAdmin.try_claim(address(pool1), address(loan1), address(dlFactory1)));

        // Admin can't claim after removed
        pat.setPoolAdmin(address(pool1), address(securityAdmin), false);                            // Add admin to allow to call the `claim()` function
        assertTrue(!securityAdmin.try_claim(address(pool1), address(loan1), address(dlFactory1)));  // Does not have permission to call `claim()` function
    }

    function test_claim_defaulting_for_zero_collateral_loan(
        uint256 apr,
        uint256 index,
        uint256 numPayments,
        uint256 requestAmount
    ) public {
        // Create Loan with 0% CR so no claimable funds are present after default
        uint256[5] memory specs = getFuzzedSpecs(apr, index, numPayments, requestAmount, 0);
        address[3] memory calcs = [address(repaymentCalc), address(lateFeeCalc), address(premiumCalc)];

        uint256 depositAmt = specs[3];
        mintFundsAndDepositIntoPool(lex, pool1, depositAmt, depositAmt);

        ILoan zero_loan = ILoan(bob.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));

        // Fund the loan by pool delegate.
        assertTrue(pat.try_fundLoan(address(pool1), address(zero_loan), address(dlFactory1), depositAmt));

        // Drawdown of the loan
        uint256 cReq = zero_loan.collateralRequiredForDrawdown(depositAmt);
        assertEq(cReq, 0);  // No collateral required on 0% collateralized loan
        bob.drawdown(address(zero_loan), depositAmt);

        // Initial claim to clear out claimable funds from drawdown
        pat.claim(address(pool1), address(zero_loan), address(dlFactory1));

        uint256 beforeBalance = usdc.balanceOf(address(bPool));
        // Time warp to default
        hevm.warp(block.timestamp + zero_loan.nextPaymentDue() + globals.defaultGracePeriod() + 1);
        pat.triggerDefault(address(pool1), address(zero_loan), address(dlFactory1));   // Triggers a "liquidation" that does not perform a swap

        assertEq(pool1.principalOut(), depositAmt);
        assertEq(usdc.balanceOf(pool1.liquidityLocker()), 0);

        uint256[7] memory claim = pat.claim(address(pool1), address(zero_loan), address(dlFactory1));
        assertEq(claim[0], 0);
        assertEq(claim[1], 0);
        assertEq(claim[2], 0);
        assertEq(claim[3], 0);
        assertEq(claim[4], 0);
        assertEq(claim[5], 0);
        assertEq(claim[6], depositAmt);

        assertEq(pool1.principalOut(), 0);

        // It should be equal to the amount recovered from the BPTs burned.
        assertEq(usdc.balanceOf(pool1.liquidityLocker()), beforeBalance - usdc.balanceOf(address(bPool)));
    }

    function test_claim_principal_accounting(
        uint256 apr,
        uint256 index,
        uint256 numPayments,
        uint256 requestAmount,
        uint256 collateralRatio
    ) public {
        /*********************************************/
        /*** Create a loan with 0% APR, 0% premium ***/
        /*********************************************/
        premiumCalc = new PremiumCalc(0);  // Flat 0% premium
        gov.setCalc(address(premiumCalc), true);

        uint256 depositAmt = generateLoanAndDepositAmount(apr, index, numPayments, requestAmount, collateralRatio);

        /**************************************************/
        /*** Mint and deposit funds into liquidity pool ***/
        /**************************************************/

        mintFundsAndDepositIntoPool(leo, pool1, 6E10 * USD,     depositAmt);
        mintFundsAndDepositIntoPool(liz, pool1, 6E10 * USD, 3 * depositAmt);
        mintFundsAndDepositIntoPool(lex, pool1, 6E10 * USD, 6 * depositAmt);

        uint256 CONST_POOL_VALUE = pool1.principalOut() + usdc.balanceOf(pool1.liquidityLocker());

        /***********************************/
        /*** Fund loan1 / loan2 (Excess) ***/
        /***********************************/

        uint256 beforeLLBalance = usdc.balanceOf(pool1.liquidityLocker());
        (uint256 totalFundedAmount, uint256[] memory fundedAmounts) = getLoanFundedAmounts(beforeLLBalance, 8, uint256(4), uint256(4));

        assertConstFundLoan(pool1, address(loan1), address(dlFactory1), fundedAmounts[0], usdc, CONST_POOL_VALUE);
        assertConstFundLoan(pool1, address(loan1), address(dlFactory1), fundedAmounts[1], usdc, CONST_POOL_VALUE);
        assertConstFundLoan(pool1, address(loan1), address(dlFactory2), fundedAmounts[2], usdc, CONST_POOL_VALUE);
        assertConstFundLoan(pool1, address(loan1), address(dlFactory2), fundedAmounts[3], usdc, CONST_POOL_VALUE);
        assertConstFundLoan(pool1, address(loan2), address(dlFactory1), fundedAmounts[4], usdc, CONST_POOL_VALUE);
        assertConstFundLoan(pool1, address(loan2), address(dlFactory1), fundedAmounts[5], usdc, CONST_POOL_VALUE);
        assertConstFundLoan(pool1, address(loan2), address(dlFactory2), fundedAmounts[6], usdc, CONST_POOL_VALUE);
        assertConstFundLoan(pool1, address(loan2), address(dlFactory2), fundedAmounts[7], usdc, CONST_POOL_VALUE);

        assertEq(pool1.principalOut(), totalFundedAmount);
        assertEq(usdc.balanceOf(pool1.liquidityLocker()), beforeLLBalance - totalFundedAmount);

        /*****************/
        /*** Draw Down ***/
        /*****************/

        drawdown(loan1, bob, loan1.requestAmount());
        drawdown(loan2, ben, loan2.requestAmount());

        /*********************************/
        /*** Make (Early) Full Payment ***/
        /*********************************/

        doFullLoanPayment(loan1, bob);  // Complete loan payment for loan1
        doFullLoanPayment(loan2, ben);  // Complete loan payment for loan2

        /******************/
        /*** Pool Claim ***/
        /******************/

        assertConstClaim(pool1, address(loan1), address(dlFactory1), usdc, CONST_POOL_VALUE);
        assertConstClaim(pool1, address(loan2), address(dlFactory1), usdc, CONST_POOL_VALUE);
        assertConstClaim(pool1, address(loan2), address(dlFactory2), usdc, CONST_POOL_VALUE);
        assertConstClaim(pool1, address(loan1), address(dlFactory2), usdc, CONST_POOL_VALUE);

        assertTrue(pool1.principalOut() < 10);
    }

    function test_claim_single_pool(
        uint256 apr,
        uint256 index,
        uint256 numPayments,
        uint256 requestAmount,
        uint256 collateralRatio
    ) public {

        uint256 depositAmt = generateLoanAndDepositAmount(apr, index, numPayments, requestAmount, collateralRatio);

        /**************************************************/
        /*** Mint and deposit funds into liquidity pool ***/
        /**************************************************/

        mintFundsAndDepositIntoPool(leo, pool1, 6E10 * USD,     depositAmt);
        mintFundsAndDepositIntoPool(liz, pool1, 6E10 * USD, 3 * depositAmt);
        mintFundsAndDepositIntoPool(lex, pool1, 6E10 * USD, 6 * depositAmt);

        /***********************************/
        /*** Fund loan1 / loan2 (Excess) ***/
        /***********************************/

        uint256 beforeLLBalance = usdc.balanceOf(pool1.liquidityLocker());
        (uint256 totalFundedAmount,  uint256[] memory fundedAmounts)  = getLoanFundedAmounts(beforeLLBalance,  8, uint256(4), uint256(4));

        assertTrue(pat.try_fundLoan(address(pool1), address(loan1), address(dlFactory1), fundedAmounts[0]));
        assertTrue(pat.try_fundLoan(address(pool1), address(loan1), address(dlFactory1), fundedAmounts[1]));
        assertTrue(pat.try_fundLoan(address(pool1), address(loan1), address(dlFactory2), fundedAmounts[2]));
        assertTrue(pat.try_fundLoan(address(pool1), address(loan1), address(dlFactory2), fundedAmounts[3]));

        assertTrue(pat.try_fundLoan(address(pool1), address(loan2), address(dlFactory1), fundedAmounts[4]));
        assertTrue(pat.try_fundLoan(address(pool1), address(loan2), address(dlFactory1), fundedAmounts[5]));
        assertTrue(pat.try_fundLoan(address(pool1), address(loan2), address(dlFactory2), fundedAmounts[6]));
        assertTrue(pat.try_fundLoan(address(pool1), address(loan2), address(dlFactory2), fundedAmounts[7]));

        assertEq(pool1.principalOut(), totalFundedAmount);
        assertEq(usdc.balanceOf(pool1.liquidityLocker()), beforeLLBalance - totalFundedAmount);

        IDebtLocker debtLocker1 = IDebtLocker(pool1.debtLockers(address(loan1), address(dlFactory1)));  // debtLocker1 = DebtLocker 1, for loan1 using dlFactory1
        IDebtLocker debtLocker2 = IDebtLocker(pool1.debtLockers(address(loan1), address(dlFactory2)));  // debtLocker2 = DebtLocker 2, for loan1 using dlFactory2
        IDebtLocker debtLocker3 = IDebtLocker(pool1.debtLockers(address(loan2), address(dlFactory1)));  // debtLocker3 = DebtLocker 3, for loan2 using dlFactory1
        IDebtLocker debtLocker4 = IDebtLocker(pool1.debtLockers(address(loan2), address(dlFactory2)));  // debtLocker4 = DebtLocker 4, for loan2 using dlFactory2

        /*****************/
        /*** Draw Down ***/
        /*****************/

        drawdown(loan1, bob, loan1.requestAmount());
        drawdown(loan2, ben, loan2.requestAmount());

        /****************************/
        /*** Make 1 Payment (1/6) ***/
        /****************************/

        doPartialLoanPayment(loan1, bob);
        doPartialLoanPayment(loan2, ben);

        /******************/
        /*** Pool Claim ***/
        /******************/

        checkClaim(debtLocker1, loan1, pat, usdc, pool1, address(dlFactory1));
        checkClaim(debtLocker2, loan1, pat, usdc, pool1, address(dlFactory2));
        checkClaim(debtLocker3, loan2, pat, usdc, pool1, address(dlFactory1));
        checkClaim(debtLocker4, loan2, pat, usdc, pool1, address(dlFactory2));

        /******************************/
        /*** Make 2 Payments (3/6)  ***/
        /******************************/

        doPartialLoanPayment(loan1, bob);  // USDC required for 2nd payment on loan1
        doPartialLoanPayment(loan2, ben);  // USDC required for 2nd payment on loan2

        doPartialLoanPayment(loan1, bob);  // USDC required for 3rd payment on loan1
        doPartialLoanPayment(loan2, ben);  // USDC required for 3rd payment on loan2

        /******************/
        /*** Pool Claim ***/
        /******************/

        checkClaim(debtLocker1, loan1, pat, usdc, pool1, address(dlFactory1));
        checkClaim(debtLocker2, loan1, pat, usdc, pool1, address(dlFactory2));
        checkClaim(debtLocker3, loan2, pat, usdc, pool1, address(dlFactory1));
        checkClaim(debtLocker4, loan2, pat, usdc, pool1, address(dlFactory2));

        /*********************************/
        /*** Make (Early) Full Payment ***/
        /*********************************/

        doFullLoanPayment(loan1, bob);  // Complete loan payment for loan1
        doFullLoanPayment(loan2, ben);  // Complete loan payment for loan2

        /******************/
        /*** Pool Claim ***/
        /******************/

        checkClaim(debtLocker1, loan1, pat, usdc, pool1, address(dlFactory1));
        checkClaim(debtLocker2, loan1, pat, usdc, pool1, address(dlFactory2));
        checkClaim(debtLocker3, loan2, pat, usdc, pool1, address(dlFactory1));
        checkClaim(debtLocker4, loan2, pat, usdc, pool1, address(dlFactory2));

        // Ensure both loans are matured.
        assertEq(uint256(loan1.loanState()), 2);
        assertEq(uint256(loan2.loanState()), 2);

        assertTrue(pool1.principalOut() < 10);
    }

    function test_claim_multiple_pools(
        uint256 apr,
        uint256 index,
        uint256 numPayments,
        uint256 requestAmount,
        uint256 collateralRatio
    ) public {

        uint256 depositAmt = generateLoanAndDepositAmount(apr, index, numPayments, requestAmount, collateralRatio);

        /*************************************************************/
        /*** Mint and deposit funds into liquidity pools (1b each) ***/
        /*************************************************************/

        mintFundsAndDepositIntoPool(leo, pool1, 10E10 * USD,     depositAmt);
        mintFundsAndDepositIntoPool(liz, pool1, 10E10 * USD, 3 * depositAmt);
        mintFundsAndDepositIntoPool(lex, pool1, 10E10 * USD, 6 * depositAmt);

        mintFundsAndDepositIntoPool(lex, pool2, 0,     depositAmt);
        mintFundsAndDepositIntoPool(leo, pool2, 0, 5 * depositAmt);
        mintFundsAndDepositIntoPool(liz, pool2, 0, 4 * depositAmt);

        /**************************/
        /*** Fund loan1 / loan2 ***/
        /**************************/
        {
            uint256 beforeLLBalance  = usdc.balanceOf(pool1.liquidityLocker());
            uint256 beforeLLBalance2 = usdc.balanceOf(pool2.liquidityLocker());
            (uint256 totalFundedAmount,  uint256[] memory fundedAmounts)  = getLoanFundedAmounts(beforeLLBalance,  8, uint256(4), uint256(4));
            (uint256 totalFundedAmount2, uint256[] memory fundedAmounts2) = getLoanFundedAmounts(beforeLLBalance2, 6, uint256(2), uint256(4));

            // Pool 1 loan 1
            assertTrue(pat.try_fundLoan(address(pool1), address(loan1), address(dlFactory1), fundedAmounts[0]));
            assertTrue(pat.try_fundLoan(address(pool1), address(loan1), address(dlFactory1), fundedAmounts[1]));
            assertTrue(pat.try_fundLoan(address(pool1), address(loan1), address(dlFactory2), fundedAmounts[2]));
            assertTrue(pat.try_fundLoan(address(pool1), address(loan1), address(dlFactory2), fundedAmounts[3]));

            // Pool 2 loan 1
            assertTrue(pam.try_fundLoan(address(pool2), address(loan1), address(dlFactory1), fundedAmounts2[0]));
            assertTrue(pam.try_fundLoan(address(pool2), address(loan1), address(dlFactory2), fundedAmounts2[1]));

            // Pool 1 Loan 2
            assertTrue(pat.try_fundLoan(address(pool1), address(loan2), address(dlFactory1), fundedAmounts[4]));
            assertTrue(pat.try_fundLoan(address(pool1), address(loan2), address(dlFactory1), fundedAmounts[5]));
            assertTrue(pat.try_fundLoan(address(pool1), address(loan2), address(dlFactory2), fundedAmounts[6]));
            assertTrue(pat.try_fundLoan(address(pool1), address(loan2), address(dlFactory2), fundedAmounts[7]));

            // Pool 2 loan 2
            assertTrue(pam.try_fundLoan(address(pool2), address(loan2), address(dlFactory1), fundedAmounts2[2]));
            assertTrue(pam.try_fundLoan(address(pool2), address(loan2), address(dlFactory1), fundedAmounts2[3]));
            assertTrue(pam.try_fundLoan(address(pool2), address(loan2), address(dlFactory2), fundedAmounts2[4]));
            assertTrue(pam.try_fundLoan(address(pool2), address(loan2), address(dlFactory2), fundedAmounts2[5]));

            // Present state checks
            assertEq(usdc.balanceOf(pool1.liquidityLocker()),           beforeLLBalance - totalFundedAmount);
            assertEq(usdc.balanceOf(pool2.liquidityLocker()),          beforeLLBalance2 - totalFundedAmount2);
            assertEq(usdc.balanceOf(address(loan1.fundingLocker())),   fundedAmounts[0] + fundedAmounts[1] + fundedAmounts[2] + fundedAmounts[3] + fundedAmounts2[0] + fundedAmounts2[1]);   // Balance of loan fl
            assertEq(usdc.balanceOf(address(loan2.fundingLocker())),   fundedAmounts[4] + fundedAmounts[5] + fundedAmounts[6] + fundedAmounts[7] + fundedAmounts2[2] + fundedAmounts2[3] + fundedAmounts2[4] + fundedAmounts2[5]);  // Balance of loan2 fl
            assertEq(loan1.balanceOf(getDL(pool1, loan1, dlFactory1)), toWad(fundedAmounts[0]) + toWad(fundedAmounts[1]));    // Balance of debtLocker1 for pool1 with dlFactory1
            assertEq(loan1.balanceOf(getDL(pool1, loan1, dlFactory2)), toWad(fundedAmounts[2]) + toWad(fundedAmounts[3]));    // Balance of debtLocker2 for pool1 with dlFactory2
            assertEq(loan2.balanceOf(getDL(pool1, loan2, dlFactory1)), toWad(fundedAmounts[4]) + toWad(fundedAmounts[5]));    // Balance of debtLocker3 for pool1 with dlFactory1
            assertEq(loan2.balanceOf(getDL(pool1, loan2, dlFactory2)), toWad(fundedAmounts[6]) + toWad(fundedAmounts[7]));    // Balance of debtLocker4 for pool1 with dlFactory2
            assertEq(loan1.balanceOf(getDL(pool2, loan1, dlFactory1)), toWad(fundedAmounts2[0]));                             // Balance of debtLocker1 for pool2 with dlFactory1
            assertEq(loan1.balanceOf(getDL(pool2, loan1, dlFactory2)), toWad(fundedAmounts2[1]));                             // Balance of debtLocker2 for pool2 with dlFactory2
            assertEq(loan2.balanceOf(getDL(pool2, loan2, dlFactory1)), toWad(fundedAmounts2[2]) + toWad(fundedAmounts2[3]));  // Balance of debtLocker3 for pool2 with dlFactory1
            assertEq(loan2.balanceOf(getDL(pool2, loan2, dlFactory2)), toWad(fundedAmounts2[4]) + toWad(fundedAmounts2[5]));  // Balance of debtLocker4 for pool2 with dlFactory2
        }

        IDebtLocker debtLocker1_pool1 = IDebtLocker(getDL(pool1, loan1, dlFactory1));  // debtLocker1_pool1 = DebtLocker 1, for pool1, for loan1 using dlFactory1
        IDebtLocker debtLocker2_pool1 = IDebtLocker(getDL(pool1, loan1, dlFactory2));  // debtLocker2_pool1 = DebtLocker 2, for pool1, for loan1 using dlFactory2
        IDebtLocker debtLocker3_pool1 = IDebtLocker(getDL(pool1, loan2, dlFactory1));  // debtLocker3_pool1 = DebtLocker 3, for pool1, for loan2 using dlFactory1
        IDebtLocker debtLocker4_pool1 = IDebtLocker(getDL(pool1, loan2, dlFactory2));  // debtLocker4_pool1 = DebtLocker 4, for pool1, for loan2 using dlFactory2
        IDebtLocker debtLocker1_pool2 = IDebtLocker(getDL(pool2, loan1, dlFactory1));  // debtLocker1_pool2 = DebtLocker 1, for pool2, for loan1 using dlFactory1
        IDebtLocker debtLocker2_pool2 = IDebtLocker(getDL(pool2, loan1, dlFactory2));  // debtLocker2_pool2 = DebtLocker 2, for pool2, for loan1 using dlFactory2
        IDebtLocker debtLocker3_pool2 = IDebtLocker(getDL(pool2, loan2, dlFactory1));  // debtLocker3_pool2 = DebtLocker 3, for pool2, for loan2 using dlFactory1
        IDebtLocker debtLocker4_pool2 = IDebtLocker(getDL(pool2, loan2, dlFactory2));  // debtLocker4_pool2 = DebtLocker 4, for pool2, for loan2 using dlFactory2

        /*****************/
        /*** Draw Down ***/
        /*****************/

        drawdown(loan1, bob, loan1.requestAmount());
        drawdown(loan2, ben, loan2.requestAmount());

        /****************************/
        /*** Make 1 Payment (1/6) ***/
        /****************************/

        doPartialLoanPayment(loan1, bob);  // USDC required for 1st payment on loan1
        doPartialLoanPayment(loan2, ben);  // USDC required for 1st payment on loan2

        /******************/
        /*** Pool Claim ***/
        /******************/

        checkClaim(debtLocker1_pool1, loan1, pat, usdc, pool1, address(dlFactory1));
        checkClaim(debtLocker2_pool1, loan1, pat, usdc, pool1, address(dlFactory2));
        checkClaim(debtLocker3_pool1, loan2, pat, usdc, pool1, address(dlFactory1));
        checkClaim(debtLocker4_pool1, loan2, pat, usdc, pool1, address(dlFactory2));

        checkClaim(debtLocker1_pool2, loan1, pam, usdc, pool2, address(dlFactory1));
        checkClaim(debtLocker2_pool2, loan1, pam, usdc, pool2, address(dlFactory2));
        checkClaim(debtLocker3_pool2, loan2, pam, usdc, pool2, address(dlFactory1));
        checkClaim(debtLocker4_pool2, loan2, pam, usdc, pool2, address(dlFactory2));

        /******************************/
        /*** Make 2 Payments (3/6)  ***/
        /******************************/

        doPartialLoanPayment(loan1, bob);  // USDC required for 2nd payment on loan1
        doPartialLoanPayment(loan2, ben);  // USDC required for 2nd payment on loan2

        doPartialLoanPayment(loan1, bob);  // USDC required for 3rd payment on loan1
        doPartialLoanPayment(loan2, ben);  // USDC required for 3rd payment on loan2

        /******************/
        /*** Pool Claim ***/
        /******************/

        checkClaim(debtLocker1_pool1, loan1, pat, usdc, pool1, address(dlFactory1));
        checkClaim(debtLocker2_pool1, loan1, pat, usdc, pool1, address(dlFactory2));
        checkClaim(debtLocker3_pool1, loan2, pat, usdc, pool1, address(dlFactory1));
        checkClaim(debtLocker4_pool1, loan2, pat, usdc, pool1, address(dlFactory2));

        checkClaim(debtLocker1_pool2, loan1, pam, usdc, pool2, address(dlFactory1));
        checkClaim(debtLocker2_pool2, loan1, pam, usdc, pool2, address(dlFactory2));
        checkClaim(debtLocker3_pool2, loan2, pam, usdc, pool2, address(dlFactory1));
        checkClaim(debtLocker4_pool2, loan2, pam, usdc, pool2, address(dlFactory2));

        /*********************************/
        /*** Make (Early) Full Payment ***/
        /*********************************/

        doFullLoanPayment(loan1, bob);  // Complete loan payment for loan1
        doFullLoanPayment(loan2, ben);  // Complete loan payment for loan2

        /******************/
        /*** Pool Claim ***/
        /******************/

        checkClaim(debtLocker1_pool1, loan1, pat, usdc, pool1, address(dlFactory1));
        checkClaim(debtLocker2_pool1, loan1, pat, usdc, pool1, address(dlFactory2));
        checkClaim(debtLocker3_pool1, loan2, pat, usdc, pool1, address(dlFactory1));
        checkClaim(debtLocker4_pool1, loan2, pat, usdc, pool1, address(dlFactory2));

        checkClaim(debtLocker1_pool2, loan1, pam, usdc, pool2, address(dlFactory1));
        checkClaim(debtLocker2_pool2, loan1, pam, usdc, pool2, address(dlFactory2));
        checkClaim(debtLocker3_pool2, loan2, pam, usdc, pool2, address(dlFactory1));
        checkClaim(debtLocker4_pool2, loan2, pam, usdc, pool2, address(dlFactory2));

        // Ensure both loans are matured.
        assertEq(uint256(loan1.loanState()), 2);
        assertEq(uint256(loan2.loanState()), 2);

        assertTrue(pool1.principalOut() < 10);
        assertTrue(pool2.principalOut() < 10);
    }

    function test_claim_external_transfers(
        uint256 depositAmt,
        uint256 transferAmtToPool,
        uint256 transferAmtToDL,
        uint256 transferAmtToLoan
    ) public {

        /**********************************************************/
        /*** Mint, deposit funds into liquidity pool, fund loan ***/
        /**********************************************************/

        depositAmt = constrictToRange(depositAmt, loan1.requestAmount(), 1_000_000_000 * USD, true);

        mintFundsAndDepositIntoPool(leo, pool1, 2_000_000_000 * USD, depositAmt);

        pat.fundLoan(address(pool1), address(loan1), address(dlFactory1), depositAmt);
        assertTrue(pool1.debtLockers(address(loan1), address(dlFactory1)) != address(0));
        assertEq(pool1.principalOut(), depositAmt);

        /*****************/
        /*** Draw Down ***/
        /*****************/

        drawdown(loan1, bob, depositAmt);

        /*****************************/
        /*** Make Interest Payment ***/
        /*****************************/

        doPartialLoanPayment(loan1, bob);

        /****************************************************/
        /*** Transfer USDC into Pool, Loan and debtLocker ***/
        /****************************************************/

        leo.approve(USDC, address(this), MAX_UINT);

        IDebtLocker debtLocker1 = IDebtLocker(pool1.debtLockers(address(loan1), address(dlFactory1)));

        uint256 poolBal_before       = usdc.balanceOf(address(pool1));
        uint256 debtLockerBal_before = usdc.balanceOf(address(debtLocker1));

        uint256 extraTransferAmtToPool = constrictToRange(transferAmtToPool, 10 * USD, 1_000_000 * USD, true);
        uint256 extraTransferAmtToDL   = constrictToRange(transferAmtToDL,   10 * USD, 1_000_000 * USD, true);
        uint256 extraTransferAmtToLoan = constrictToRange(transferAmtToLoan, 10 * USD, 1_000_000 * USD, true);

        usdc.transferFrom(address(leo), address(pool1),       extraTransferAmtToPool);
        usdc.transferFrom(address(leo), address(debtLocker1), extraTransferAmtToDL);
        usdc.transferFrom(address(leo), address(loan1),       extraTransferAmtToLoan);

        uint256 poolBal_after       = usdc.balanceOf(address(pool1));
        uint256 debtLockerBal_after = usdc.balanceOf(address(debtLocker1));

        assertEq(poolBal_after - poolBal_before,             extraTransferAmtToPool);
        assertEq(debtLockerBal_after - debtLockerBal_before, extraTransferAmtToDL);

        poolBal_before       = poolBal_after;
        debtLockerBal_before = debtLockerBal_after;

        checkClaim(debtLocker1, loan1, pat, usdc, pool1, address(dlFactory1));

        poolBal_after       = usdc.balanceOf(address(pool1));
        debtLockerBal_after = usdc.balanceOf(address(debtLocker1));

        assertTrue(poolBal_after - poolBal_before < 10);  // Collects some rounding dust
        assertEq(debtLockerBal_after, debtLockerBal_before);

        /*************************/
        /*** Make Full Payment ***/
        /*************************/

        doFullLoanPayment(loan1, bob);

        /*********************************************************/
        /*** Check claim with existing balances in DL and Pool ***/
        /*** Transfer more funds into Loan                     ***/
        /*********************************************************/

        // Transfer funds into Loan to make principalClaim > principalOut
        extraTransferAmtToLoan = constrictToRange(transferAmtToLoan, 200_000 * USD, 1_000_000 * USD, true);
        usdc.transferFrom(address(leo), address(loan1), extraTransferAmtToLoan);

        poolBal_before       = usdc.balanceOf(address(pool1));
        debtLockerBal_before = usdc.balanceOf(address(debtLocker1));

        checkClaim(debtLocker1, loan1, pat, usdc, pool1, address(dlFactory1));

        poolBal_after       = usdc.balanceOf(address(pool1));
        debtLockerBal_after = usdc.balanceOf(address(debtLocker1));

        assertTrue(poolBal_after - poolBal_before < 10);  // Collects some rounding dust
        assertEq(debtLockerBal_after, debtLockerBal_before);

        assertTrue(pool1.principalOut() < 10);
    }

    /***************/
    /*** Helpers ***/
    /***************/

    function assertConstFundLoan(IPool pool, address _loan, address dlFactory, uint256 amt, IERC20 liquidityAsset, uint256 constPoolVal) internal returns (bool) {
        assertTrue(pat.try_fundLoan(address(pool), _loan,  dlFactory, amt));
        assertTrue(isConstantPoolValue(pool, liquidityAsset, constPoolVal));
    }

    function assertConstClaim(IPool pool, address _loan, address dlFactory, IERC20 liquidityAsset, uint256 constPoolVal) internal returns (bool) {
        pat.claim(address(pool), _loan, dlFactory);
        assertTrue(isConstantPoolValue(pool, liquidityAsset, constPoolVal));
    }

    function isConstantPoolValue(IPool pool, IERC20 liquidityAsset, uint256 constPoolVal) internal view returns (bool) {
        return pool.principalOut() + liquidityAsset.balanceOf(pool.liquidityLocker()) == constPoolVal;
    }

    function calcAllotment(uint256 newAmt, uint256 totalClaim, uint256 totalNewAmt) internal pure returns (uint256) {
        return newAmt == uint256(0) ? uint256(0) : newAmt.mul(totalClaim).div(totalNewAmt);
    }

    function getDL(IPool pool, ILoan loan, IDebtLockerFactory dlFactory) internal view returns (address) {
        return pool.debtLockers(address(loan), address(dlFactory));
    }

    function generateLoanAndDepositAmount(
        uint256 apr,
        uint256 index,
        uint256 numPayments,
        uint256 requestAmount,
        uint256 collateralRatio
    ) internal returns (uint256 depositAmt) {
        uint256[5] memory specs = getFuzzedSpecs(apr, index, numPayments, requestAmount, collateralRatio);
        address[3] memory calcs = [address(repaymentCalc), address(lateFeeCalc), address(premiumCalc)];

        loan1 = Loan(bob.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));
        loan2 = Loan(ben.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));

        depositAmt = constrictToRange(specs[3], 100 * USD, 1E10 * USD, true);  // Fund value should be between 100 USD - 1B USD
        uint256 estimatedLLBalance = 10 * depositAmt;
        if (estimatedLLBalance < specs[3] * 2) {
            uint256 delta = specs[3] * 2 - estimatedLLBalance;
            depositAmt = (estimatedLLBalance + delta / 10);
        }
    }

    function getLoanFundedAmounts(uint256 beforeLLBalance, uint256 rounds, uint256 loan1FundedCount, uint256 loan2FundedCount) internal view returns (uint256, uint256[] memory) {
        uint256 maxAmountPerFundLoan = beforeLLBalance / rounds;
        uint256 totalFundedAmount    = 0;

        uint256[] memory fundedCount     = new uint256[](2);
        uint256[] memory fundedAmounts   = new uint256[](rounds);
        uint256[] memory amtFundedToLoan = new uint256[](2);

        fundedCount[0] = loan1FundedCount;
        fundedCount[1] = loan2FundedCount;

        for (uint256 i = 0; i < rounds; i++) {
            uint256 minAmt     = i == 0 ? 100 * USD : fundedAmounts[i - 1];
            uint256 fundAmt    = i == 0 ? maxAmountPerFundLoan : i * fundedAmounts[i - 1];
            fundedAmounts[i]   = constrictToRange(fundAmt, minAmt, maxAmountPerFundLoan, true);
            totalFundedAmount += fundedAmounts[i];
        }

        for (uint256 j = 0; j < fundedCount.length; j++) {
            for (uint256 i = 0; i < fundedCount[0]; i++) {
                amtFundedToLoan[j] += fundedAmounts[i];
            }
        }

        if (amtFundedToLoan[0] < loan1.requestAmount()) {
            fundedAmounts[0]  += loan1.requestAmount() - amtFundedToLoan[0];
            totalFundedAmount += loan1.requestAmount() - amtFundedToLoan[0];
        }

        if (amtFundedToLoan[1] < loan2.requestAmount()) {
            fundedAmounts[4]  += loan2.requestAmount() - amtFundedToLoan[1];
            totalFundedAmount += loan2.requestAmount() - amtFundedToLoan[1];
        }
        return (totalFundedAmount, fundedAmounts);
    }

    function checkClaim(IDebtLocker debtLocker, ILoan _loan, PoolDelegate pd, IERC20 liquidityAsset, IPool pool, address dlFactory) internal {
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
        uint256[7] memory claim    = pd.claim(address(pool), address(_loan), address(dlFactory));

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

        for (uint256 i = 0; i < 4; i++) sumNetNew += (loanData[i] - debtLockerData[i]);

        for (uint256 i = 0; i < 4; i++) {
            assertEq(debtLockerData[i + 4], loanData[i]);  // DL updated to reflect loan state
            // Category portion of claim * DL asset balance
            // Eg. (interestClaimed / totalClaimed) * balance = Portion of total claim balance that is interest
            assertEq(calcAllotment(loanData[i] - debtLockerData[i], claim[0], sumNetNew), claim[i + 1]);

            sumTransfer += balances[i + 6] - balances[i + 1];  // Sum up all transfers that occurred from claim
        }

        assertEq(claim[0], sumTransfer);  // Assert balance from withdrawFunds equals sum of transfers

        assertEq(  balances[5] - balances[0], 0);    // DL should have transferred ALL funds claimed to LP
        assertTrue(balances[6] - balances[1] < 10);  // LP should have transferred ALL funds claimed to LL, SL, and PD (with rounding error)

        assertEq(  balances[7] - balances[2], claim[3] + claim[1] * pool.delegateFee() / 10_000);  // Pool delegate claim (feePaid + delegateFee portion of interest)
        assertEq(  balances[8] - balances[3],            claim[1] * pool.stakingFee()  / 10_000);  // Staking Locker claim (feePaid + stakingFee portion of interest)

        // LiquidityLocker balance change should EXACTLY equal state variable change
        assertEq(balances[9] - balances[4], (beforePrincipalOut - pool.principalOut()) + (pool.interestSum() - beforeInterestSum));

        // Normal case, principalClaim <= principalOut
        if (claim[2] + claim[4] + claim[5] <= beforePrincipalOut) {
            // interestSum incremented by remainder of interest
            withinPrecision(
                pool.interestSum() - beforeInterestSum,
                claim[1] - ((claim[1] * pool.delegateFee() / 10_000) + (claim[1] * pool.stakingFee() / 10_000)),
                11
            );
            // principalOut decremented by principal paid plus excess
            assertTrue(beforePrincipalOut - pool.principalOut() == claim[2] + claim[4] + claim[5]);
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
