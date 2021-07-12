// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { TestUtil } from "test/TestUtil.sol";

contract PremiumCalcTest is TestUtil {

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

    function test_premium(uint56 _loanAmt, uint256 premiumFee) public {
        uint256 loanAmt = uint256(_loanAmt) + 10 ** 6;  // uint56(-1) = ~72b * 10 ** 6

        premiumFee = premiumFee % 10_000;

        setUpRepayments(loanAmt, 100, 1, 1);

        mint("USDC",      address(bob),   loanAmt * 1000);  // Mint enough to pay interest
        bob.approve(USDC, address(loan1), loanAmt * 1000);

        uint256 beforeBal = IERC20(USDC).balanceOf(address(bob));

        (uint256 total,         uint256 principal,         uint256 interest)         = loan1.getFullPayment();                         // USDC required for payment on loan
        (uint256 total_premium, uint256 principal_premium, uint256 interest_premium) = premiumCalc.getPremiumPayment(address(loan1));  // USDC required for payment on loan

        assertEq(total,         total_premium);
        assertEq(principal, principal_premium);
        assertEq(interest,   interest_premium);

        assertEq(interest, principal * premiumCalc.premiumFee() / 10_000);

        bob.makeFullPayment(address(loan1));

        uint256 afterBal = IERC20(USDC).balanceOf(address(bob));

        assertEq(beforeBal - afterBal, total);
    }

    function test_late_premium(uint56 _loanAmt, uint256 apr, uint16 index, uint16 numPayments, uint256 lateFee) public {
        uint256 loanAmt = constrictToRange(_loanAmt, 10_000 * USD, 100 * 1E9 * USD, true);  // $10k to $100b, non zero

        apr     = apr     % 10_000;
        lateFee = lateFee % 10_000;

        setUpRepayments(loanAmt, apr, index, numPayments);

        mint("USDC",      address(bob),  loanAmt * 1000);  // Mint enough to pay interest
        bob.approve(USDC, address(loan1), loanAmt * 1000);

        uint256 beforeBal = IERC20(USDC).balanceOf(address(bob));

        hevm.warp(loan1.nextPaymentDue() + 1);  // Payment is late

        (uint256 total,         uint256 principal,         uint256 interest)         = loan1.getFullPayment();                         // USDC required for payment on loan
        (uint256 total_premium, uint256 principal_premium, uint256 interest_premium) = premiumCalc.getPremiumPayment(address(loan1));  // USDC required for payment on loan

        // Get late fee from regular interest payment
        (,, uint256 interest_calc) = repaymentCalc.getNextPayment(address(loan1));
        uint256 interest_late = lateFeeCalc.getLateFee(interest_calc);  // USDC required for payment on loan

        assertEq(total,        total_premium + interest_late);
        assertEq(principal,                principal_premium);
        assertEq(interest,  interest_premium + interest_late);

        assertEq(interest, principal * premiumCalc.premiumFee() / 10_000 + interest_late);

        bob.makeFullPayment(address(loan1));

        uint256 afterBal = IERC20(USDC).balanceOf(address(bob));

        assertEq(beforeBal - afterBal, total);
    }

}
