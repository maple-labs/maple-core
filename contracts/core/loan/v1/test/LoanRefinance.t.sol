// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import { TestUtil } from "../../../../test/TestUtil.sol";

import { Loan } from "../Loan.sol";

contract LoanRefinanceTest is TestUtil {

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

    function test_refinance() public {
        /**
        Create Loan
        Fund Loan with PD1
        Fund Loan with PD2
        Make Payments
        Deploy new Loan
        Create DL2 funding for zero
         */

        uint256 loanAmount = 10_000_000 * USD;

        uint256[5] memory specs = [uint256(1000), uint256(90), uint256(30), loanAmount, uint256(2000)];
        address[3] memory calcs = [address(repaymentCalc), address(lateFeeCalc), address(premiumCalc)];

        Loan loan = Loan(bob.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));

        mint("USDC", address(leo),        loanAmount);
        leo.approve(USDC, address(pool1), loanAmount);
        leo.deposit(address(pool1),       loanAmount);

        pat.fundLoan(address(pool1), address(loan), address(dlFactory1), loanAmount);

        // Approve collateral and drawdown loan.
        drawdown(loan, loan.requestAmount());

        (uint256 total, uint256 principal, uint256 interest, uint256 due,) = loan.getNextPayment();

        mint("USDC", address(bob),       total);
        bob.approve(USDC, address(loan), total);
        bob.makePayment(address(loan));

        mint("USDC", address(bob),       total);
        bob.approve(USDC, address(loan), total);
        bob.makePayment(address(loan));
    }
}
