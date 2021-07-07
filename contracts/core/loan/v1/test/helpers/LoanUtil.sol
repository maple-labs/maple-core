// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "test/TestUtil.sol";

contract LoanUtil is TestUtil {

    function createAndFundLoan(
        uint256 apr,
        uint256 index,
        uint256 numPayments,
        uint256 requestAmount,
        uint256 collateralRatio,
        uint256 fundAmount,
        address _loanFactory
    )
        internal returns (ILoan loan)
    {
        uint256[5] memory specs = getFuzzedSpecs(apr, index, numPayments, requestAmount, collateralRatio);
        address[3] memory calcs = [address(repaymentCalc), address(lateFeeCalc), address(premiumCalc)];

        loan = bob.createLoan(_loanFactory, USDC, WETH, address(flFactory), address(clFactory), specs, calcs);

        fundAmount = constrictToRange(fundAmount, specs[3], 1E10 * USD, true);  // Fund between requestAmount and 10b USD

        mint("USDC", address(leo),        fundAmount);
        leo.approve(USDC, address(pool1), fundAmount);
        leo.deposit(address(pool1),       fundAmount);

        pat.fundLoan(address(pool1), address(loan), address(dlFactory1), fundAmount);
    }

    function drawdown_test(
        ILoan loan,
        uint256 fundAmount,
        uint256 drawdownAmount,
        uint256 investorFee,
        uint256 treasuryFee
    ) internal {

        assertTrue(!ben.try_drawdown(address(loan), drawdownAmount));                                  // Non-borrower can't drawdown
        if (loan.collateralRatio() > 0) assertTrue(!bob.try_drawdown(address(loan), drawdownAmount));  // Can't drawdown without approving collateral

        uint256 reqCollateral = loan.collateralRequiredForDrawdown(drawdownAmount);
        mint("WETH", address(bob),       reqCollateral);
        bob.approve(WETH, address(loan), reqCollateral);

        assertTrue(!bob.try_drawdown(address(loan), loan.requestAmount() - 1));  // Can't drawdown less than requestAmount
        assertTrue(!bob.try_drawdown(address(loan),           fundAmount + 1));  // Can't drawdown more than fundingLocker balance

        assertEq(weth.balanceOf(address(bob)),          reqCollateral);  // Borrower collateral balance
        assertEq(usdc.balanceOf(loan.fundingLocker()),     fundAmount);  // FundingLocker liquidityAsset balance
        assertEq(usdc.balanceOf(address(loan)),                     0);  // Loan liquidityAsset balance
        assertEq(loan.principalOwed(),                              0);  // Principal owed
        assertEq(uint256(loan.loanState()),                         0);  // Loan state: Ready

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
        assertEq(weth.balanceOf(address(loan.collateralLocker())), reqCollateral);  // CollateralLocker collateral balance

        assertEq(usdc.balanceOf(loan.fundingLocker()),                                  0);  // FundingLocker liquidityAsset balance
        assertEq(usdc.balanceOf(address(loan)), fundAmount - drawdownAmount + investorFee);  // Loan liquidityAsset balance
        assertEq(loan.principalOwed(),                                     drawdownAmount);  // Principal owed
        assertEq(uint256(loan.loanState()),                                             1);  // Loan state: Active

        withinDiff(usdc.balanceOf(address(bob)), drawdownAmount - (investorFee + treasuryFee), 1);  // Borrower liquidityAsset balance

        assertEq(loan.nextPaymentDue(), block.timestamp + loan.paymentIntervalSeconds());  // Next payment due timestamp calculated from time of drawdown

        // Fee related variables post-check.
        assertEq(loan.feePaid(),                                    investorFee);  // Drawdown amount
        assertEq(loan.excessReturned(),             fundAmount - drawdownAmount);  // Principal owed
        assertEq(usdc.balanceOf(address(treasury)),                 treasuryFee);  // Treasury loanAsset balance

        // Test FDT accounting
        address debtLocker = pool1.debtLockers(address(loan), address(dlFactory1));
        assertEq(loan.balanceOf(debtLocker), fundAmount * WAD / USD);
        withinDiff(loan.withdrawableFundsOf(address(debtLocker)), fundAmount - drawdownAmount + investorFee, 1);

        // Can't drawdown() loan after it has already been called.
        assertTrue(!bob.try_drawdown(address(loan), drawdownAmount));
    }
}