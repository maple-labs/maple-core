// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

contract LoanLiquidationTest is TestUtil {

    function setUp() public {

        setUpGlobals();
        setUpTokens();
        setUpOracles();
        setUpFactories();
        setUpCalcs();
        setUpActors();
        setUpBalancerPool();
        setUpLiquidityPool();
        createLoans();

        /*** Mint balances to relevant actors ***/
        mint("WETH", address(bob),         100 ether);
        mint("WBTC", address(bob),          10 * BTC);
        mint("USDC", address(leo),     100_000 * USD);
        mint("USDC", address(bob),     100_000 * USD);
        mint("USDC", address(this), 50_000_000 * USD);

        /*** LP deposits USDC into Pool ***/
        leo.approve(USDC, address(pool), MAX_UINT);
        leo.deposit(address(pool), 5000 * USD); 
    }

    function createAndFundLoan(address _interestStructure, address _collateral, uint256 collateralRatio) internal returns (Loan loan) {
        uint256[5] memory specs = [500, 90, 30, uint256(1000 * USD), collateralRatio];
        address[3] memory calcs = [_interestStructure, address(lateFeeCalc), address(premiumCalc)];

        loan = bob.createLoan(address(loanFactory), USDC, _collateral, address(flFactory), address(clFactory), specs, calcs);

        pat.fundLoan(address(pool), address(loan), address(dlFactory), 1000 * USD); 

        bob.approve(_collateral, address(loan), MAX_UINT);
        assertTrue(bob.try_drawdown(address(loan), 1000 * USD));     // Borrow draws down 1000 USDC
    }

    function performLiquidationAssertions(Loan loan) internal {
        // Fetch pre-state variables.
        address collateralLocker  = loan.collateralLocker();
        address collateralAsset   = address(loan.collateralAsset());
        uint256 collateralBalance = IERC20(collateralAsset).balanceOf(address(collateralLocker));

        uint256 principalOwed_pre      = loan.principalOwed();
        uint256 liquidityAssetLoan_pre = IERC20(USDC).balanceOf(address(loan));
        uint256 liquidityAssetBorr_pre = IERC20(USDC).balanceOf(address(bob));

        // Warp to late payment.
        hevm.warp(block.timestamp + loan.nextPaymentDue() + globals.defaultGracePeriod() + 1);

        // Pre-state triggerDefault() checks.
        assertEq(uint256(loan.loanState()),                                                     1);
        assertEq(IERC20(collateralAsset).balanceOf(address(collateralLocker)),  collateralBalance);

        pat.triggerDefault(address(pool), address(loan), address(dlFactory));

        {
            uint256 principalOwed_post      = loan.principalOwed();
            uint256 liquidityAssetLoan_post = IERC20(USDC).balanceOf(address(loan));
            uint256 liquidityAssetBorr_post = IERC20(USDC).balanceOf(address(bob));
            uint256 amountLiquidated        = loan.amountLiquidated();
            uint256 amountRecovered         = loan.amountRecovered();
            uint256 defaultSuffered         = loan.defaultSuffered();
            uint256 liquidationExcess       = loan.liquidationExcess();

            // Post-state triggerDefault() checks.
            assertEq(uint256(loan.loanState()),                                     4);
            assertEq(IERC20(collateralAsset).balanceOf(address(collateralLocker)),  0);
            assertEq(amountLiquidated,                              collateralBalance);

            if (amountRecovered > principalOwed_pre) {
                assertEq(liquidityAssetBorr_post - liquidityAssetBorr_pre, liquidationExcess);
                assertEq(principalOwed_post,                                               0);
                assertEq(liquidationExcess,              amountRecovered - principalOwed_pre);
                assertEq(defaultSuffered,                                                  0);
                assertEq(
                    amountRecovered,                              
                    (liquidityAssetBorr_post - liquidityAssetBorr_pre) + (liquidityAssetLoan_post - liquidityAssetLoan_pre)
                );
            }
            else {
                assertEq(principalOwed_post,             principalOwed_pre - amountRecovered);
                assertEq(defaultSuffered,                                 principalOwed_post);
                assertEq(liquidationExcess,                                                0);
                assertEq(amountRecovered,   liquidityAssetLoan_post - liquidityAssetLoan_pre);
            }
        }
    }

    function test_basic_liquidation() public {
        // Triangular uniswap path
        Loan wbtcLoan = createAndFundLoan(address(repaymentCalc), WBTC, 2000);
        performLiquidationAssertions(wbtcLoan);

        // Bilateral uniswap path
        Loan wethLoan = createAndFundLoan(address(repaymentCalc), WETH, 2000);
        performLiquidationAssertions(wethLoan);

        // collateralAsset == liquidityAsset 
        Loan usdcLoan = createAndFundLoan(address(repaymentCalc), USDC, 2000);
        performLiquidationAssertions(usdcLoan);

        // Zero collateralization
        Loan wethLoan2 = createAndFundLoan(address(repaymentCalc), WETH, 0);
        performLiquidationAssertions(wethLoan2);
    }
}
