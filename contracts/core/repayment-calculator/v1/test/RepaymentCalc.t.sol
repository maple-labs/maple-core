// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import { SafeMath } from "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { TestUtil } from "test/TestUtil.sol";

contract RepaymentCalcTest is TestUtil {

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

    function test_repayments(uint256 _loanAmt, uint16 apr, uint16 index, uint16 numPayments) public {
        uint256 loanAmt = constrictToRange(_loanAmt, 10_000 * USD, 100 * 1E9 * USD, true);  // $10k to $100b, non zero

        apr = apr % 10_000;

        setUpRepayments(loanAmt, uint256(apr), index, numPayments);

        // Calculate theoretical values and sum up actual values
        uint256 totalPaid;
        uint256 sumTotal;
        {
            uint256 paymentIntervalDays = loan1.paymentIntervalSeconds().div(1 days);
            uint256 totalInterest       = loanAmt * apr / 10_000 * paymentIntervalDays / 365 * loan1.paymentsRemaining();
                    totalPaid           = loanAmt + totalInterest;
        }

        (uint256 lastTotal,, uint256 lastInterest,,) = loan1.getNextPayment();

        mint("USDC",      address(bob),   loanAmt * 1000);  // Mint enough to pay interest
        bob.approve(USDC, address(loan1), loanAmt * 1000);

        uint256 beforeBal = IERC20(USDC).balanceOf(address(bob));

        while (loan1.paymentsRemaining() > 0) {
            (uint256 total,      uint256 principal,      uint256 interest,,)    = loan1.getNextPayment();                        // USDC required for payment on loan
            (uint256 total_calc, uint256 principal_calc, uint256 interest_calc) = repaymentCalc.getNextPayment(address(loan1));  // USDC required for payment on loan

            assertEq(total,         total_calc);
            assertEq(principal, principal_calc);
            assertEq(interest,   interest_calc);

            sumTotal += total;

            bob.makePayment(address(loan1));

            if (loan1.paymentsRemaining() > 0) {
                assertEq(total,        lastTotal);
                assertEq(interest,  lastInterest);
                assertEq(total,         interest);
                assertEq(principal,            0);
            } else {
                assertEq(total,     principal + interest);
                assertEq(principal,              loanAmt);
                withinPrecision(totalPaid, sumTotal, 8);
                assertEq(beforeBal - IERC20(USDC).balanceOf(address(bob)), sumTotal);  // Pays back all principal, plus interest
            }

            lastTotal    = total;
            lastInterest = interest;
        }
    }

}
