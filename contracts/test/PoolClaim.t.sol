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
        gov.setValidLoanFactory(address(loanFactory), true);
    }

    function test_claim_permissions() public {
        // Finalizing the Pool
        finalizePool(pool, pat, true);

        // Add liquidity into the pool (Dan is an LP, but still won't be able to claim)
        mintFundsAndDepositIntoPool(lex, pool, 10_000 * USD, 10_000 * USD);

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
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!securityAdmin.try_claim(address(pool), address(loan), address(dlFactory)));
        
        // Unpause protocol and claim()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(securityAdmin.try_claim(address(pool), address(loan), address(dlFactory)));

        // Admin can't claim after removed
        pat.setAdmin(address(pool), address(securityAdmin), false);                                // Add admin to allow to call the `claim()` function
        assertTrue(!securityAdmin.try_claim(address(pool), address(loan), address(dlFactory)));   // Does not have permission to call `claim()` function
    }

    function test_claim_defaulting_for_zero_collateral_loan() public {
        // Finalizing the Pool
        finalizePool(pool, pat, true);

        //  Mint 10000 USDC into this LP account & add liquidity
        mintFundsAndDepositIntoPool(lex, pool, 10_000 * USD, 10_000 * USD);

        // Create Loan with 0% CR so no claimable funds are present after default
        uint256[5] memory specs = [500, 180, 30, uint256(1000 * USD), 0];
        address[3] memory calcs = [address(repaymentCalc), address(lateFeeCalc), address(premiumCalc)];

        Loan zero_loan = bob.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);

        // Fund the loan by pool delegate.
        assertTrue(pat.try_fundLoan(address(pool), address(zero_loan), address(dlFactory), 10_000 * USD));

        // Drawdown of the loan
        uint cReq = zero_loan.collateralRequiredForDrawdown(10_000 * USD); // wETH required for 15000 USDC drawdown on loan
        assertEq(cReq, 0); // No collateral required on 0% collateralized loan
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

        finalizePool(pool, pat, true);

        /**************************************************/
        /*** Mint and deposit funds into liquidity pool ***/
        /**************************************************/

        mintFundsAndDepositIntoPool(leo, pool, 1_000_000_000 * USD, 100_000_000 * USD); // 10%
        mintFundsAndDepositIntoPool(liz, pool, 1_000_000_000 * USD, 300_000_000 * USD); // 30%
        mintFundsAndDepositIntoPool(lex, pool, 1_000_000_000 * USD, 600_000_000 * USD); // 60%


        uint256 CONST_POOL_VALUE = pool.principalOut() + IERC20(USDC).balanceOf(pool.liquidityLocker());

        /************************************/
        /*** Fund loan / loan2 (Excess) ***/
        /************************************/

        assertConstFundLoan(pool, address(loan),  address(dlFactory),  100_000_000 * USD, IERC20(USDC), CONST_POOL_VALUE);
        assertConstFundLoan(pool, address(loan),  address(dlFactory),  100_000_000 * USD, IERC20(USDC), CONST_POOL_VALUE);
        assertConstFundLoan(pool, address(loan),  address(dlFactory2), 200_000_000 * USD, IERC20(USDC), CONST_POOL_VALUE);
        assertConstFundLoan(pool, address(loan),  address(dlFactory2), 200_000_000 * USD, IERC20(USDC), CONST_POOL_VALUE);
        assertConstFundLoan(pool, address(loan2), address(dlFactory),   50_000_000 * USD, IERC20(USDC), CONST_POOL_VALUE);
        assertConstFundLoan(pool, address(loan2), address(dlFactory),   50_000_000 * USD, IERC20(USDC), CONST_POOL_VALUE);
        assertConstFundLoan(pool, address(loan2), address(dlFactory2), 150_000_000 * USD, IERC20(USDC), CONST_POOL_VALUE);
        assertConstFundLoan(pool, address(loan2), address(dlFactory2), 150_000_000 * USD, IERC20(USDC), CONST_POOL_VALUE);
        
        assertEq(pool.principalOut(), 1_000_000_000 * USD);
        assertEq(IERC20(USDC).balanceOf(pool.liquidityLocker()), 0);

        /*****************/
        /*** Draw Down ***/
        /*****************/

        drawdown(loan,  bob, 100_000_000 * USD); // wETH required for 100_000_000 USDC drawdown on loan
        drawdown(loan2, ben, 100_000_000 * USD); // wETH required for 100_000_000 USDC drawdown on loan2
        
        /*********************************/
        /*** Make (Early) Full Payment ***/
        /*********************************/

        doFullLoanPayment(loan,  bob);  // Complete loan payment for loan
        doFullLoanPayment(loan2, ben);  // Complete loan payment for loan2
        
        /******************/
        /*** Pool Claim ***/
        /******************/
           
        assertConstClaim(pool, address(loan),  address(dlFactory),  IERC20(USDC), CONST_POOL_VALUE);
        assertConstClaim(pool, address(loan2), address(dlFactory),  IERC20(USDC), CONST_POOL_VALUE);
        assertConstClaim(pool, address(loan2), address(dlFactory2), IERC20(USDC), CONST_POOL_VALUE);
        assertConstClaim(pool, address(loan),  address(dlFactory2), IERC20(USDC), CONST_POOL_VALUE);
        
        assertTrue(pool.principalOut() < 10);
    }

    function test_claim_singleLP() public {

        /*******************************/
        /*** Finalize liquidity pool ***/
        /*******************************/

        finalizePool(pool, pat, true);

        /**************************************************/
        /*** Mint and deposit funds into liquidity pool ***/
        /**************************************************/
        
        mintFundsAndDepositIntoPool(leo, pool, 1_000_000_000 * USD, 100_000_000 * USD); // 10%
        mintFundsAndDepositIntoPool(liz, pool, 1_000_000_000 * USD, 300_000_000 * USD); // 30%
        mintFundsAndDepositIntoPool(lex, pool, 1_000_000_000 * USD, 600_000_000 * USD); // 60%

        /**********************************/
        /*** Fund loan / loan2 (Excess) ***/
        /**********************************/
        
        assertTrue(pat.try_fundLoan(address(pool), address(loan),  address(dlFactory),  100_000_000 * USD));
        assertTrue(pat.try_fundLoan(address(pool), address(loan),  address(dlFactory),  100_000_000 * USD));
        assertTrue(pat.try_fundLoan(address(pool), address(loan),  address(dlFactory2), 200_000_000 * USD));
        assertTrue(pat.try_fundLoan(address(pool), address(loan),  address(dlFactory2), 200_000_000 * USD));

        assertTrue(pat.try_fundLoan(address(pool), address(loan2), address(dlFactory),   50_000_000 * USD));
        assertTrue(pat.try_fundLoan(address(pool), address(loan2), address(dlFactory),   50_000_000 * USD));
        assertTrue(pat.try_fundLoan(address(pool), address(loan2), address(dlFactory2), 150_000_000 * USD));
        assertTrue(pat.try_fundLoan(address(pool), address(loan2), address(dlFactory2), 150_000_000 * USD));
        

        assertEq(pool.principalOut(), 1_000_000_000 * USD);
        assertEq(IERC20(USDC).balanceOf(pool.liquidityLocker()), 0);

        DebtLocker debtLocker1 = DebtLocker(pool.debtLockers(address(loan),  address(dlFactory)));  // debtLocker1 = DebtLocker 1, for loan using dlFactory
        DebtLocker debtLocker2 = DebtLocker(pool.debtLockers(address(loan),  address(dlFactory2)));  // debtLocker2 = DebtLocker 2, for loan using dlFactory2
        DebtLocker debtLocker3 = DebtLocker(pool.debtLockers(address(loan2), address(dlFactory)));  // debtLocker3 = DebtLocker 3, for loan2 using dlFactory
        DebtLocker debtLocker4 = DebtLocker(pool.debtLockers(address(loan2), address(dlFactory2)));  // debtLocker4 = DebtLocker 4, for loan2 using dlFactory2

        /*****************/
        /*** Draw Down ***/
        /*****************/

        drawdown(loan,  bob, 100_000_000 * USD); // wETH required for 100_000_000 USDC drawdown on loan
        drawdown(loan2, ben, 100_000_000 * USD); // wETH required for 100_000_000 USDC drawdown on loan2
        
        /****************************/
        /*** Make 1 Payment (1/6) ***/
        /****************************/

        doPartialLoanPayment(loan,  bob); // USDC required for 1st payment on loan
        doPartialLoanPayment(loan2, ben); // USDC required for 1st payment on loan2
        
        /******************/
        /*** Pool Claim ***/
        /******************/
   
        checkClaim(debtLocker1, loan,  pat, IERC20(USDC), pool, address(dlFactory));
        checkClaim(debtLocker2, loan,  pat, IERC20(USDC), pool, address(dlFactory2));
        checkClaim(debtLocker3, loan2, pat, IERC20(USDC), pool, address(dlFactory));
        checkClaim(debtLocker4, loan2, pat, IERC20(USDC), pool, address(dlFactory2));

        /******************************/
        /*** Make 2 Payments (3/6)  ***/
        /******************************/

        doPartialLoanPayment(loan,  bob); // USDC required for 2nd payment on loan
        doPartialLoanPayment(loan2, ben); // USDC required for 2nd payment on loan2

        doPartialLoanPayment(loan,  bob); // USDC required for 3rd payment on loan
        doPartialLoanPayment(loan2, ben); // USDC required for 3rd payment on loan2
        
        /******************/
        /*** Pool Claim ***/
        /******************/

        checkClaim(debtLocker1, loan,  pat, IERC20(USDC), pool, address(dlFactory));
        checkClaim(debtLocker2, loan,  pat, IERC20(USDC), pool, address(dlFactory2));
        checkClaim(debtLocker3, loan2, pat, IERC20(USDC), pool, address(dlFactory));
        checkClaim(debtLocker4, loan2, pat, IERC20(USDC), pool, address(dlFactory2));
        
        /*********************************/
        /*** Make (Early) Full Payment ***/
        /*********************************/
        
        doFullLoanPayment(loan,  bob);  // Complete loan payment for loan
        doFullLoanPayment(loan2, ben);  // Complete loan payment for loan2
        
        /******************/
        /*** Pool Claim ***/
        /******************/

        checkClaim(debtLocker1, loan,  pat, IERC20(USDC), pool, address(dlFactory));
        checkClaim(debtLocker2, loan,  pat, IERC20(USDC), pool, address(dlFactory2));
        checkClaim(debtLocker3, loan2, pat, IERC20(USDC), pool, address(dlFactory));
        checkClaim(debtLocker4, loan2, pat, IERC20(USDC), pool, address(dlFactory2));

        // Ensure both loans are matured.
        assertEq(uint256(loan.loanState()),  2);
        assertEq(uint256(loan2.loanState()), 2);

        assertTrue(pool.principalOut() < 10);
    }
    
    function test_claim_multipleLP() public {

        /******************************************/
        /*** Stake & Finalize 2 Liquidity Pools ***/
        /******************************************/
        address stakeLocker1 = pool.stakeLocker();
        address stakeLocker2 = pool2.stakeLocker();

        finalizePool(pool,  pat, true);
        finalizePool(pool2, pam, true);
       
        address liqLocker1 = pool.liquidityLocker();
        address liqLocker2 = pool2.liquidityLocker();

        /*************************************************************/
        /*** Mint and deposit funds into liquidity pools (1b each) ***/
        /*************************************************************/

        mintFundsAndDepositIntoPool(leo, pool, 1_000_000_000 * USD, 100_000_000 * USD); // 10%
        mintFundsAndDepositIntoPool(liz, pool, 1_000_000_000 * USD, 300_000_000 * USD); // 30%
        mintFundsAndDepositIntoPool(lex, pool, 1_000_000_000 * USD, 600_000_000 * USD); // 60%

        mintFundsAndDepositIntoPool(leo, pool2, 0, 500_000_000 * USD); // 50%
        mintFundsAndDepositIntoPool(liz, pool2, 0, 400_000_000 * USD); // 40%
        mintFundsAndDepositIntoPool(lex, pool2, 0, 100_000_000 * USD); // 10%

        
        address fundingLocker  = loan.fundingLocker();
        address fundingLocker2 = loan2.fundingLocker();

        /***************************/
        /*** Fund loan / loan2 ***/
        /***************************/
        
        // LP 1 Vault 1
        assertTrue(pat.try_fundLoan(address(pool), address(loan),  address(dlFactory),  25_000_000 * USD));  // Fund loan using dlFactory for 25m USDC
        assertTrue(pat.try_fundLoan(address(pool), address(loan),  address(dlFactory),  25_000_000 * USD));  // Fund loan using dlFactory for 25m USDC, again, 50m USDC total
        assertTrue(pat.try_fundLoan(address(pool), address(loan),  address(dlFactory2), 25_000_000 * USD));  // Fund loan using dlFactory2 for 25m USDC
        assertTrue(pat.try_fundLoan(address(pool), address(loan),  address(dlFactory2), 25_000_000 * USD));  // Fund loan using dlFactory2 for 25m USDC (no excess), 100m USDC total

        // LP 2 Vault 1
        assertTrue(pam.try_fundLoan(address(pool2), address(loan),  address(dlFactory),  50_000_000 * USD));  // Fund loan using dlFactory for 50m USDC (excess), 150m USDC total
        assertTrue(pam.try_fundLoan(address(pool2), address(loan),  address(dlFactory2), 50_000_000 * USD));  // Fund loan using dlFactory2 for 50m USDC (excess), 200m USDC total

        // LP 1 Vault 2
        assertTrue(pat.try_fundLoan(address(pool), address(loan2),  address(dlFactory),  50_000_000 * USD));  // Fund loan2 using dlFactory for 50m USDC
        assertTrue(pat.try_fundLoan(address(pool), address(loan2),  address(dlFactory),  50_000_000 * USD));  // Fund loan2 using dlFactory for 50m USDC, again, 100m USDC total
        assertTrue(pat.try_fundLoan(address(pool), address(loan2),  address(dlFactory2), 50_000_000 * USD));  // Fund loan2 using dlFactory2 for 50m USDC
        assertTrue(pat.try_fundLoan(address(pool), address(loan2),  address(dlFactory2), 50_000_000 * USD));  // Fund loan2 using dlFactory2 for 50m USDC again, 200m USDC total

        // LP 2 Vault 2
        assertTrue(pam.try_fundLoan(address(pool2), address(loan2),  address(dlFactory),  100_000_000 * USD));  // Fund loan2 using dlFactory for 100m USDC
        assertTrue(pam.try_fundLoan(address(pool2), address(loan2),  address(dlFactory),  100_000_000 * USD));  // Fund loan2 using dlFactory for 100m USDC, again, 400m USDC total
        assertTrue(pam.try_fundLoan(address(pool2), address(loan2),  address(dlFactory2), 100_000_000 * USD));  // Fund loan2 using dlFactory2 for 100m USDC (excess)
        assertTrue(pam.try_fundLoan(address(pool2), address(loan2),  address(dlFactory2), 100_000_000 * USD));  // Fund loan2 using dlFactory2 for 100m USDC (excess), 600m USDC total
        
        
        DebtLocker debtLocker1_pool1 = DebtLocker(pool.debtLockers(address(loan),  address(dlFactory)));    // debtLocker1_pool1 = DebtLocker 1, for pool, for loan using dlFactory
        DebtLocker debtLocker2_pool1 = DebtLocker(pool.debtLockers(address(loan),  address(dlFactory2)));   // debtLocker2_pool1 = DebtLocker 2, for pool, for loan using dlFactory2
        DebtLocker debtLocker3_pool1 = DebtLocker(pool.debtLockers(address(loan2), address(dlFactory)));    // debtLocker3_pool1 = DebtLocker 3, for pool, for loan2 using dlFactory
        DebtLocker debtLocker4_pool1 = DebtLocker(pool.debtLockers(address(loan2), address(dlFactory2)));   // debtLocker4_pool1 = DebtLocker 4, for pool, for loan2 using dlFactory2
        DebtLocker debtLocker1_pool2 = DebtLocker(pool2.debtLockers(address(loan),  address(dlFactory)));   // debtLocker1_pool2 = DebtLocker 1, for pool2, for loan using dlFactory
        DebtLocker debtLocker2_pool2 = DebtLocker(pool2.debtLockers(address(loan),  address(dlFactory2)));  // debtLocker2_pool2 = DebtLocker 2, for pool2, for loan using dlFactory2
        DebtLocker debtLocker3_pool2 = DebtLocker(pool2.debtLockers(address(loan2), address(dlFactory)));   // debtLocker3_pool2 = DebtLocker 3, for pool2, for loan2 using dlFactory
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

        drawdown(loan,  bob, 100_000_000 * USD); // wETH required for 100m USDC drawdown on loan
        drawdown(loan2, ben, 300_000_000 * USD); // wETH required for 300m USDC drawdown on loan2
        
        /****************************/
        /*** Make 1 Payment (1/6) ***/
        /****************************/

        doPartialLoanPayment(loan,  bob); // USDC required for 1st payment on loan
        doPartialLoanPayment(loan2, ben); // USDC required for 1st payment on loan2
        
        /*******************/
        /***  Pool Claim ***/
        /*******************/
        
        checkClaim(debtLocker1_pool1, loan,  pat, IERC20(USDC), pool, address(dlFactory));
        checkClaim(debtLocker2_pool1, loan,  pat, IERC20(USDC), pool, address(dlFactory2));
        checkClaim(debtLocker3_pool1, loan2, pat, IERC20(USDC), pool, address(dlFactory));
        checkClaim(debtLocker4_pool1, loan2, pat, IERC20(USDC), pool, address(dlFactory2));

        checkClaim(debtLocker1_pool2, loan,  pam, IERC20(USDC), pool2, address(dlFactory));
        checkClaim(debtLocker2_pool2, loan,  pam, IERC20(USDC), pool2, address(dlFactory2));
        checkClaim(debtLocker3_pool2, loan2, pam, IERC20(USDC), pool2, address(dlFactory));
        checkClaim(debtLocker4_pool2, loan2, pam, IERC20(USDC), pool2, address(dlFactory2));
        

        /******************************/
        /*** Make 2 Payments (3/6)  ***/
        /******************************/

        doPartialLoanPayment(loan,  bob); // USDC required for 2nd payment on loan
        doPartialLoanPayment(loan2, ben); // USDC required for 2nd payment on loan2

        doPartialLoanPayment(loan,  bob); // USDC required for 3rd payment on loan
        doPartialLoanPayment(loan2, ben); // USDC required for 3rd payment on loan2

        /*******************/
        /***  Pool Claim ***/
        /*******************/
        
        checkClaim(debtLocker1_pool1, loan,  pat, IERC20(USDC), pool, address(dlFactory));
        checkClaim(debtLocker2_pool1, loan,  pat, IERC20(USDC), pool, address(dlFactory2));
        checkClaim(debtLocker3_pool1, loan2, pat, IERC20(USDC), pool, address(dlFactory));
        checkClaim(debtLocker4_pool1, loan2, pat, IERC20(USDC), pool, address(dlFactory2));

        checkClaim(debtLocker1_pool2, loan,  pam, IERC20(USDC), pool2, address(dlFactory));
        checkClaim(debtLocker2_pool2, loan,  pam, IERC20(USDC), pool2, address(dlFactory2));
        checkClaim(debtLocker3_pool2, loan2, pam, IERC20(USDC), pool2, address(dlFactory));
        checkClaim(debtLocker4_pool2, loan2, pam, IERC20(USDC), pool2, address(dlFactory2));
        
        
        /*********************************/
        /*** Make (Early) Full Payment ***/
        /*********************************/

        doFullLoanPayment(loan,  bob);  // Complete loan payment for loan
        doFullLoanPayment(loan2, ben);  // Complete loan payment for loan2
        
        /*******************/
        /***  Pool Claim ***/
        /*******************/
        
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
        

        assertTrue(pool.principalOut() < 10);
        assertTrue(pool2.principalOut() < 10);
    }

    function test_claim_external_transfers() public {
        /*******************************/
        /*** Finalize liquidity pool ***/
        /*******************************/

        finalizePool(pool, pat, true);

        /**********************************************************/
        /*** Mint, deposit funds into liquidity pool, fund loan ***/
        /**********************************************************/

        mintFundsAndDepositIntoPool(leo, pool, 1_000_000_000 * USD, 100_000_000 * USD);

        pat.fundLoan(address(pool), address(loan),  address(dlFactory), 100_000_000 * USD);
        assertTrue(pool.debtLockers(address(loan),  address(dlFactory)) != address(0));
        assertEq(pool.principalOut(), 100_000_000 * USD);

        /*****************/
        /*** Draw Down ***/
        /*****************/

        drawdown(loan, bob, 100_000_000 * USD);

        /*****************************/
        /*** Make Interest Payment ***/
        /*****************************/

        doPartialLoanPayment(loan, bob);

        /****************************************************/
        /*** Transfer USDC into Pool, Loan and debtLocker ***/
        /****************************************************/

        leo.approve(USDC, address(this), MAX_UINT);

        DebtLocker debtLocker1 = DebtLocker(pool.debtLockers(address(loan),  address(dlFactory)));

        uint256 poolBal_before       = IERC20(USDC).balanceOf(address(pool));
        uint256 debtLockerBal_before = IERC20(USDC).balanceOf(address(debtLocker1));

        IERC20(USDC).transferFrom(address(leo), address(pool),        1000 * USD);
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
        

        /*************************/
        /*** Make Full Payment ***/
        /*************************/

        doFullLoanPayment(loan, bob);

        /*********************************************************/
        /*** Check claim with existing balances in DL and Pool ***/
        /*** Transfer more funds into Loan                     ***/
        /*********************************************************/
        
        // Transfer funds into Loan to make principalClaim > principalOut
        IERC20(USDC).transferFrom(address(leo), address(loan), 200000 * USD);

        poolBal_before       = IERC20(USDC).balanceOf(address(pool));
        debtLockerBal_before = IERC20(USDC).balanceOf(address(debtLocker1));

        checkClaim(debtLocker1, loan, pat, IERC20(USDC), pool, address(dlFactory));

        poolBal_after       = IERC20(USDC).balanceOf(address(pool));
        debtLockerBal_after = IERC20(USDC).balanceOf(address(debtLocker1));

        assertTrue(poolBal_after - poolBal_before < 10);  // Collects some rounding dust
        assertEq(debtLockerBal_after, debtLockerBal_before);

        assertTrue(pool.principalOut() < 10);
    }

    /***************/
    /*** Helpers ***/
    /***************/

    function assertConstFundLoan(Pool pool, address _loan, address dlFactory, uint256 amt, IERC20 liquidityAsset, uint256 constPoolVal) internal returns(bool) {
        assertTrue(pat.try_fundLoan(address(pool), _loan,  dlFactory, amt));
        assertTrue(isConstantPoolValue(pool, liquidityAsset, constPoolVal));
    }

    function assertConstClaim(Pool pool, address _loan, address dlFactory, IERC20 liquidityAsset, uint256 constPoolVal) internal returns(bool) {
        pat.claim(address(pool), _loan, dlFactory);
        assertTrue(isConstantPoolValue(pool, liquidityAsset, constPoolVal));
    }

    function isConstantPoolValue(Pool pool, IERC20 liquidityAsset, uint256 constPoolVal) internal view returns(bool) {
        return pool.principalOut() + liquidityAsset.balanceOf(pool.liquidityLocker()) == constPoolVal;
    }

    function calcAllotment(uint256 newAmt, uint256 totalClaim, uint256 totalNewAmt) internal pure returns (uint256) {
        return newAmt == uint256(0) ? uint256(0) : newAmt.mul(totalClaim).div(totalNewAmt);
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

        for (uint i = 0; i < 4; i++) sumNetNew += (loanData[i] - debtLockerData[i]);

        for (uint i = 0; i < 4; i++) {
            assertEq(debtLockerData[i + 4], loanData[i]);  // DL updated to reflect loan state
            // Category portion of claim * DL asset balance 
            // Eg. (interestClaimed / totalClaimed) * balance = Portion of total claim balance that is interest
            assertEq(calcAllotment(loanData[i] - debtLockerData[i], claim[0], sumNetNew), claim[i + 1]);

            sumTransfer += balances[i + 6] - balances[i + 1]; // Sum up all transfers that occured from claim
        }
        
        assertEq(claim[0], sumTransfer); // Assert balance from withdrawFunds equals sum of transfers
        
        assertEq(  balances[5] - balances[0], 0);      // DL should have transferred ALL funds claimed to LP
        assertTrue(balances[6] - balances[1] < 10);    // LP should have transferred ALL funds claimed to LL, SL, and PD (with rounding error)
        assertEq(  balances[7] - balances[2], claim[3] + claim[1] * pool.delegateFee() / 10_000);  // Pool delegate claim (feePaid + delegateFee portion of interest)
        assertEq(  balances[8] - balances[3],            claim[1] * pool.stakingFee()  / 10_000);  // Staking Locker claim (feePaid + stakingFee portion of interest)

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