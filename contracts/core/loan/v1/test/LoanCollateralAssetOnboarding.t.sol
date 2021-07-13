// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "test/TestUtil.sol";

contract LoanCollateralAssetOnboardingTest is TestUtil {

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

    function createLoanAndDrawdown(
        uint256 apr,
        uint256 index,
        uint256 numPayments,
        uint256 requestAmount,
        uint256 collateralRatio,
        uint256 fundAmount,
        uint256 drawdownAmount,
        bytes32 collateralSymbol
    ) public {
        IERC20 collateralAsset = IERC20(tokens[collateralSymbol].addr);
        Loan loan = createAndFundLoan(apr, index, numPayments, requestAmount, collateralRatio, fundAmount, address(collateralAsset));
        address fundingLocker = loan.fundingLocker();
        fundAmount = usdc.balanceOf(fundingLocker);

        drawdownAmount = constrictToRange(drawdownAmount, loan.requestAmount(), fundAmount, true);

        assertTrue(!ben.try_drawdown(address(loan), drawdownAmount));                                  // Non-borrower can't drawdown
        if (loan.collateralRatio() > 0) assertTrue(!bob.try_drawdown(address(loan), drawdownAmount));  // Can't drawdown without approving collateral

        uint256 reqCollateral = loan.collateralRequiredForDrawdown(drawdownAmount);
        mint(collateralSymbol,                address(bob),  reqCollateral);
        bob.approve(address(collateralAsset), address(loan), reqCollateral);

        assertTrue(!bob.try_drawdown(address(loan), loan.requestAmount() - 1));  // Can't drawdown less than requestAmount
        assertTrue(!bob.try_drawdown(address(loan),           fundAmount + 1));  // Can't drawdown more than fundingLocker balance

        assertEq(collateralAsset.balanceOf(address(bob)),  reqCollateral);  // Borrower collateral balance

        assertEq(usdc.balanceOf(fundingLocker),    fundAmount);  // FundingLocker liquidityAsset balance
        assertEq(usdc.balanceOf(address(loan)),             0);  // Loan liquidityAsset balance
        assertEq(loan.principalOwed(),                      0);  // Principal owed
        assertEq(uint256(loan.loanState()),                 0);  // Loan state: Ready

        // Fee related variables pre-check.
        assertEq(loan.feePaid(),                            0);  // feePaid amount
        assertEq(loan.excessReturned(),                     0);  // excessReturned amount
        assertEq(usdc.balanceOf(address(treasury)),         0);  // Treasury liquidityAsset balance

        // Pause protocol and attempt drawdown()
        emergencyAdmin.setProtocolPause(IMapleGlobals(address(globals)), true);
        assertTrue(!bob.try_drawdown(address(loan), drawdownAmount));

        // Unpause protocol and drawdown()
        emergencyAdmin.setProtocolPause(IMapleGlobals(address(globals)), false);
        assertTrue(bob.try_drawdown(address(loan), drawdownAmount));

        assertEq(collateralAsset.balanceOf(address(bob)),                                 0);  // Borrower collateral balance
        assertEq(collateralAsset.balanceOf(address(loan.collateralLocker())), reqCollateral);  // CollateralLocker collateral balance

        uint256 investorFee = drawdownAmount * globals.investorFee() / 10_000;
        uint256 treasuryFee = drawdownAmount * globals.treasuryFee() / 10_000;

        assertEq(usdc.balanceOf(fundingLocker),                                         0);  // FundingLocker liquidityAsset balance
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


    function test_collateralOnboardingAave1(
        uint256 apr,
        uint256 index,
        uint256 numPayments,
        uint256 requestAmount,
        uint256 collateralRatio,
        uint256 fundAmount,
        uint256 drawdownAmount
    ) public {
        // Assertion for the oracle price check.
        assertTrue(globals.getLatestPrice(AAVE) > uint256(0));

        createLoanAndDrawdown(apr, index, numPayments, requestAmount, collateralRatio, fundAmount, drawdownAmount, "AAVE");
    }

}
