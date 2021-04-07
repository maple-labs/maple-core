// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

contract GulpTest is TestUtil {

    using SafeMath for uint256;

    function setUp() public {
        setUpGlobals();
        setUpTokens();
        setUpOracles();
        setUpFactories();
        setUpCalcs();
        setUpActors();
        setUpBalancerPoolForStakers();
        setUpLiquidityPool();
        createLoan();
    }

    function setUpLoanAndDrawdown() public {
        mint("USDC", address(leo), 10_000_000 * USD);  // Mint USDC to LP
        leo.approve(USDC, address(pool), MAX_UINT);    // LP approves USDC

        leo.deposit(address(pool), 10_000_000 * USD);                                      // LP deposits 10m USDC to Pool
        pat.fundLoan(address(pool), address(loan), address(dlFactory), 10_000_000 * USD);  // PD funds loan for 10m USDC

        uint cReq = loan.collateralRequiredForDrawdown(10_000_000 * USD);  // WETH required for 100_000_000 USDC drawdown on loan
        mint("WETH", address(bob), cReq);                                  // Mint WETH to borrower
        bob.approve(WETH, address(loan), MAX_UINT);                        // Borrower approves WETH
        bob.drawdown(address(loan), 10_000_000 * USD);                     // Borrower draws down 10m USDC
    }

    function test_gulp() public {

        Governor fakeGov = new Governor();
        fakeGov.setGovGlobals(globals);  // Point to globals created by gov

        gov.setGovTreasury(treasury);
        fakeGov.setGovTreasury(treasury);

        // Drawdown on loan will transfer fee to MPL token contract.
        setUpLoanAndDrawdown();

        // Treasury processes fees, sends to MPL token holders.
        // treasury.distributeToHolders();
        assertTrue(!fakeGov.try_distributeToHolders());
        assertTrue(     gov.try_distributeToHolders());

        uint256 totalFundsToken = IERC20(USDC).balanceOf(address(mpl));
        uint256 mplBal          = mpl.balanceOf(address(bPool));
        uint256 earnings        = mpl.withdrawableFundsOf(address(bPool));

        assertEq(totalFundsToken, loan.principalOwed() * globals.treasuryFee() / 10_000);
        assertEq(mplBal,          100_000 * WAD);
        withinDiff(earnings, totalFundsToken * mplBal / mpl.totalSupply(), 1);

        // MPL is held by Balancer Pool, claim on behalf of BPool.
        mpl.withdrawFundsOnBehalf(address(bPool));

        uint256 usdcBal_preGulp = bPool.getBalance(USDC);

        bPool.gulp(USDC); // Update BPool with gulp(token).

        uint256 usdcBal_postGulp = bPool.getBalance(USDC);

        assertEq(usdcBal_preGulp,  50_000_000 * USD);
        assertEq(usdcBal_postGulp, usdcBal_preGulp + earnings); // USDC is transferred into balancer pool, increasing value of MPL
    }
}
