// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "test/TestUtil.sol";

contract LateFeeCalcTest is TestUtil {

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

    function test_late_fee(uint56 _loanAmt, uint256 apr, uint16 index, uint16 numPayments, uint256 lateFee) public {
        uint256 loanAmt = constrictToRange(_loanAmt, 10_000 * USD, 100 * 1E9 * USD, true);  // $10k to $100b, non zero

        apr     = apr     % 10_000;
        lateFee = lateFee % 10_000;

        setUpRepayments(loanAmt, apr, index, numPayments);

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
}
