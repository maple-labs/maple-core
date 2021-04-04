// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

contract CalcsTest is TestUtil {

    using SafeMath for uint256;

    function setUp() public {
        setUpGlobals();
        setUpPoolDelegate();
        createBorrower();
        setUpFactories();
        setUpCalcs();
        setUpTokens();
        setUpOracles();
        setUpBalancerPool();
        setUpLiquidityPool();
    }

    function setUpRepayments(uint256 loanAmt, uint256 apr, uint16 index, uint16 numPayments, uint256 lateFee, uint256 premiumFee) public {
        uint16[10] memory paymentIntervalArray = [1, 2, 5, 7, 10, 15, 30, 60, 90, 360];

        uint256 paymentInterval = paymentIntervalArray[index % 10];
        uint256 termDays        = paymentInterval * (numPayments % 100);

        {
            // Mint "infinite" amount of USDC and deposit into pool
            mint("USDC", address(this), loanAmt);
            IERC20(USDC).approve(address(pool), uint(-1));
            pool.deposit(loanAmt);

            // Create loan, fund loan, draw down on loan
            address[3] memory calcs = [address(repaymentCalc), address(lateFeeCalc), address(premiumCalc)];
            uint256[5] memory specs = [apr, termDays, paymentInterval, loanAmt, 2000];
            loan = bob.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory),  specs, calcs);
        }

        assertTrue(pat.try_fundLoan(address(pool), address(loan),  address(dlFactory), loanAmt));

        {
            uint cReq = loan.collateralRequiredForDrawdown(loanAmt); // wETH required for 1_000 USDC drawdown on loan
            mint("WETH", address(bob), cReq);
            bob.approve(WETH, address(loan), cReq);
            bob.drawdown(address(loan), loanAmt);
        }
    }

    function test_repayments(uint256 _loanAmt, uint16 apr, uint16 index, uint16 numPayments) public {
        uint256 loanAmt = constrictToRange(_loanAmt, 10_000 * USD, 100 * 1E9 * USD, true);  // $10k to $100b, non zero

        apr = apr % 10_000;

        setUpRepayments(loanAmt, uint256(apr), index, numPayments, 100, 100);

        // Calculate theoretical values and sum up actual values
        uint256 totalPaid;
        uint256 sumTotal;
        {
            uint256 paymentIntervalDays = loan.paymentIntervalSeconds().div(1 days);
            uint256 totalInterest       = loanAmt * apr / 10_000 * paymentIntervalDays / 365 * loan.paymentsRemaining();
                    totalPaid           = loanAmt + totalInterest;
        }

        (uint256 lastTotal,, uint256 lastInterest,,) = loan.getNextPayment();

        mint("USDC",      address(bob),  loanAmt * 1000); // Mint enough to pay interest
        bob.approve(USDC, address(loan), loanAmt * 1000);

        uint256 beforeBal = IERC20(USDC).balanceOf(address(bob));

        while (loan.paymentsRemaining() > 0) {

            (uint256 total,      uint256 principal,      uint256 interest,,)    = loan.getNextPayment();                       // USDC required for payment on loan
            (uint256 total_calc, uint256 principal_calc, uint256 interest_calc) = repaymentCalc.getNextPayment(address(loan)); // USDC required for payment on loan

            assertEq(total,         total_calc);
            assertEq(principal, principal_calc);
            assertEq(interest,   interest_calc);

            sumTotal += total;

            bob.makePayment(address(loan));

            if (loan.paymentsRemaining() > 0) {
                assertEq(total,        lastTotal);
                assertEq(interest,  lastInterest);
                assertEq(total,         interest);
                assertEq(principal,            0);
            } else {
                assertEq(total,     principal + interest);
                assertEq(principal,              loanAmt);
                withinPrecision(totalPaid, sumTotal, 8);
                assertEq(beforeBal - IERC20(USDC).balanceOf(address(bob)), sumTotal); // Pays back all principal, plus interest
            }

            lastTotal    = total;
            lastInterest = interest;
        }
    }

    function test_late_fee(uint56 _loanAmt, uint256 apr, uint16 index, uint16 numPayments, uint256 lateFee) public {
        uint256 loanAmt = constrictToRange(_loanAmt, 10_000 * USD, 100 * 1E9 * USD, true);  // $10k to $100b, non zero

        apr     = apr     % 10_000;
        lateFee = lateFee % 10_000;

        setUpRepayments(loanAmt, apr, index, numPayments, lateFee, 100);

        // Calculate theoretical values and sum up actual values
        uint256 totalPaid;
        uint256 sumTotal;
        {
            uint256 paymentIntervalDays = loan.paymentIntervalSeconds().div(1 days);
            uint256 totalInterest       = loanAmt * apr / 10_000 * paymentIntervalDays / 365 * loan.paymentsRemaining();
                    totalPaid           = loanAmt + totalInterest + totalInterest * lateFeeCalc.lateFee() / 10_000;
        }

        hevm.warp(loan.nextPaymentDue() + 1);  // Payment is late
        (uint256 lastTotal,,,,) =  loan.getNextPayment();

        mint("USDC",      address(bob),  loanAmt * 1000); // Mint enough to pay interest
        bob.approve(USDC, address(loan), loanAmt * 1000);

        uint256 beforeBal = IERC20(USDC).balanceOf(address(bob));

        while (loan.paymentsRemaining() > 0) {
            hevm.warp(loan.nextPaymentDue() + 1);  // Payment is late

            (uint256 total,      uint256 principal,      uint256 interest,,)    = loan.getNextPayment();                       // USDC required for payment on loan
            (uint256 total_calc, uint256 principal_calc, uint256 interest_calc) = repaymentCalc.getNextPayment(address(loan)); // USDC required for payment on loan

            uint256 interest_late = lateFeeCalc.getLateFee(interest_calc);  // USDC required for payment on loan

            assertEq(total,        total_calc + interest_late);  // Late fee is added to total
            assertEq(principal,                principal_calc);
            assertEq(interest,  interest_calc + interest_late);

            sumTotal += total;

            bob.makePayment(address(loan));

            if (loan.paymentsRemaining() > 0) {
                assertEq(total,     lastTotal);
                assertEq(total,      interest);
                assertEq(principal,         0);

                assertEq(interest_late, total_calc * lateFeeCalc.lateFee() / 10_000);
            } else {
                assertEq(total,     principal + interest);
                assertEq(principal,              loanAmt);
                withinPrecision(totalPaid, sumTotal, 8);
                assertEq(beforeBal - IERC20(USDC).balanceOf(address(bob)), sumTotal); // Pays back all principal, plus interest
            }

            lastTotal = total;
        }
    }

    function test_premium(uint56 _loanAmt, uint256 premiumFee) public {
        uint256 loanAmt = uint256(_loanAmt) + 10 ** 6;  // uint56(-1) = ~72b * 10 ** 6

        premiumFee = premiumFee % 10_000;

        setUpRepayments(loanAmt, 100, 1, 1, 100, premiumFee);

        mint("USDC",      address(bob),  loanAmt * 1000); // Mint enough to pay interest
        bob.approve(USDC, address(loan), loanAmt * 1000);

        uint256 beforeBal = IERC20(USDC).balanceOf(address(bob));

        (uint256 total,         uint256 principal,         uint256 interest)         = loan.getFullPayment();                         // USDC required for payment on loan
        (uint256 total_premium, uint256 principal_premium, uint256 interest_premium) = premiumCalc.getPremiumPayment(address(loan));  // USDC required for payment on loan

        assertEq(total,         total_premium);
        assertEq(principal, principal_premium);
        assertEq(interest,   interest_premium);

        assertEq(interest, principal * premiumCalc.premiumFee() / 10_000);

        bob.makeFullPayment(address(loan));

        uint256 afterBal = IERC20(USDC).balanceOf(address(bob));

        assertEq(beforeBal - afterBal, total);
    }
}
