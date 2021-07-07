// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "core/loan/v1/test/helpers/LoanUtil.sol";

contract LoanV2Test is LoanUtil {

    function setUp() public {
        setUpGlobals();
        setUpTokens();
        setUpOracles();
        setUpFactories();
        setUpCalcs();
        setUpActors();
        setUpBalancerPool();
        setUpLiquidityPool();
        createLoanV2();
    }

    function test_drawdown(
        uint256 apr,
        uint256 index,
        uint256 numPayments,
        uint256 requestAmount,
        uint256 collateralRatio,
        uint256 fundAmount,
        uint256 drawdownAmount
    )
        public
    {
        ILoan loan = createAndFundLoan(apr, index, numPayments, requestAmount, collateralRatio, fundAmount, address(loanFactoryV2));
        fundAmount = usdc.balanceOf(loan.fundingLocker());

        drawdownAmount = constrictToRange(drawdownAmount, loan.requestAmount(), fundAmount, true);

        uint256 investorFee = drawdownAmount * globals.investorFee() / 10_000 * loan.termDays() / 365;
        uint256 treasuryFee = drawdownAmount * globals.treasuryFee() / 10_000 * loan.termDays() / 365;

        drawdown_test(loan, fundAmount, drawdownAmount, investorFee, treasuryFee);
    }

}