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

    function drawdown(Loan loan, uint256 drawdownAmount) internal returns (uint256 reqCollateral) {
        reqCollateral = loan.collateralRequiredForDrawdown(drawdownAmount);
        mint("WETH", address(bob), reqCollateral);
        bob.approve(WETH, address(loan), reqCollateral);
        bob.drawdown(address(loan), drawdownAmount);  // Borrow draws down on loan
    }

    function test_refinance() public {
        uint256 loanAmount = 10_000_000 * USD;

        uint256[5] memory specs = [uint256(1000), uint256(90), uint256(30), loanAmount, uint256(2000)];
        address[3] memory calcs = [address(repaymentCalc), address(lateFeeCalc), address(premiumCalc)];

        Loan loan1 = Loan(bob.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));

        mint("USDC", address(leo),        loanAmount);
        leo.approve(USDC, address(pool1), loanAmount);
        leo.deposit(address(pool1),       loanAmount);

        pat.fundLoan(address(pool1), address(loan1), address(dlFactory1), loanAmount);

        // Approve collateral and drawdown loan1.
        uint256 collateralPosted = drawdown(loan1, loan1.requestAmount());

        {
            (uint256 total, uint256 principal, uint256 interest, uint256 due,) = loan1.getNextPayment();

            mint("USDC", address(bob),        total);
            bob.approve(USDC, address(loan1), total);
            bob.makePayment(address(loan1));

            mint("USDC", address(bob),        total);
            bob.approve(USDC, address(loan1), total);
            bob.makePayment(address(loan1));
        }        

        Loan loan2 = Loan(bob.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));

        bob.setPreviousLoan(address(loan2), address(loan1));  // Set Loan to use for refinance

        pat.fundLoan(address(pool1), address(loan2), address(dlFactory1), 0);

        address debtLocker1 = pool1.debtLockers(address(loan1), address(dlFactory1));
        address debtLocker2 = pool1.debtLockers(address(loan2), address(dlFactory1));


        assertEq(weth.balanceOf(loan1.collateralLocker()), collateralPosted);
        assertEq(weth.balanceOf(loan2.collateralLocker()), 0);

        assertEq(loan1.totalSupply(), loanAmount);
        assertEq(loan2.totalSupply(), 0);

        assertEq(loan1.principalOwed(), loanAmount);
        assertEq(loan2.principalOwed(), 0);

        pat.refinanceLoan(address(debtLocker2), address(debtLocker1), loanAmount);

        assertEq(weth.balanceOf(loan1.collateralLocker()), 0);
        assertEq(weth.balanceOf(loan2.collateralLocker()), collateralPosted);

        assertEq(loan1.totalSupply(), 0);
        assertEq(loan2.totalSupply(), loanAmount);

        assertEq(loan1.principalOwed(), 0);
        assertEq(loan2.principalOwed(), loanAmount);
    }
}
