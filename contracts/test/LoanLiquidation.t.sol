// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "./user/Borrower.sol";
import "./user/Governor.sol";
import "./user/Lender.sol";

import "../RepaymentCalc.sol";
import "../CollateralLockerFactory.sol";
import "../FundingLockerFactory.sol";
import "../LateFeeCalc.sol";
import "../LoanFactory.sol";
import "../MapleGlobals.sol";
import "../PremiumCalc.sol";

import "../interfaces/IERC20Details.sol";
import "../interfaces/ILoan.sol";

import "../oracles/ChainlinkOracle.sol";
import "../oracles/UsdOracle.sol";

import "module/maple-token/contracts/MapleToken.sol";

contract Treasury { }

contract LoanLiquidationTest is TestUtil {

    Borrower                          ali;
    Governor                          gov;
    Lender                            bob;

    RepaymentCalc           repaymentCalc;
    CollateralLockerFactory     clFactory;
    FundingLockerFactory        flFactory;
    LateFeeCalc               lateFeeCalc;
    LoanFactory               loanFactory;
    MapleToken                        mpl;
    MapleGlobals                  globals;
    PremiumCalc               premiumCalc;
    Treasury                          trs;
    ChainlinkOracle            wethOracle;
    ChainlinkOracle            wbtcOracle;
    UsdOracle                   usdOracle;

    ERC20                      fundsToken;

    uint256 constant public MAX_UINT = uint256(-1);

    function setUp() public {

        ali = new Borrower();   // Actor: Borrower of the Loan.
        gov = new Governor();   // Actor: Governor of Maple.
        bob = new Lender();     // Actor: Individual lender.

        mpl           = new MapleToken("MapleToken", "MAPL", USDC);
        globals       = gov.createGlobals(address(mpl), BPOOL_FACTORY, address(0));  // Setup Maple Globals.
        flFactory     = new FundingLockerFactory();
        clFactory     = new CollateralLockerFactory();
        repaymentCalc = new RepaymentCalc();
        lateFeeCalc   = new LateFeeCalc(0);   // Flat 0% fee
        premiumCalc   = new PremiumCalc(500); // Flat 5% premium
        loanFactory   = new LoanFactory(address(globals));
        trs           = new Treasury();

        gov.setCalc(address(repaymentCalc), true);
        gov.setCalc(address(lateFeeCalc),   true);
        gov.setCalc(address(premiumCalc),   true);
        gov.setCollateralAsset(WETH,        true);
        gov.setCollateralAsset(WBTC,        true);
        gov.setCollateralAsset(USDC,        true);
        gov.setLoanAsset(USDC,              true);
        
        wethOracle = new ChainlinkOracle(tokens["WETH"].orcl, WETH, address(this));
        wbtcOracle = new ChainlinkOracle(tokens["WBTC"].orcl, WBTC, address(this));
        usdOracle  = new UsdOracle();
        
        gov.setPriceOracle(WETH, address(wethOracle));
        gov.setPriceOracle(WBTC, address(wbtcOracle));
        gov.setPriceOracle(USDC, address(usdOracle));

        gov.setValidSubFactory(address(loanFactory), address(flFactory), true);
        gov.setValidSubFactory(address(loanFactory), address(clFactory), true);

        gov.setDefaultUniswapPath(WETH, USDC, USDC);
        gov.setDefaultUniswapPath(WBTC, USDC, WETH);
        gov.setMapleTreasury(address(trs));

        mint("WETH", address(ali),    100 ether);
        mint("WBTC", address(ali),     10 * BTC);
        mint("USDC", address(bob), 100000 * USD);
        mint("USDC", address(ali), 100000 * USD);
    }

    function createAndFundLoan(address _interestStructure, address _collateral) internal returns (Loan loan) {
        uint256[6] memory specs = [500, 90, 30, uint256(1000 * USD), 2000, 7];
        address[3] memory calcs = [_interestStructure, address(lateFeeCalc), address(premiumCalc)];

        loan = ali.createLoan(address(loanFactory), USDC, _collateral, address(flFactory), address(clFactory), specs, calcs);

        bob.approve(USDC, address(loan), 5000 * USD);

        bob.fundLoan(address(loan), 5000 * USD, address(ali));
        ali.approve(_collateral, address(loan), MAX_UINT);
        assertTrue(ali.try_drawdown(address(loan), 1000 * USD));     // Borrow draws down 1000 USDC
    }

    function performLiquidationAssertions(Loan loan) internal {
        // Fetch pre-state variables.
        address collateralLocker  = loan.collateralLocker();
        address collateralAsset   = address(loan.collateralAsset());
        uint256 collateralBalance = IERC20(collateralAsset).balanceOf(address(collateralLocker));

        uint256 principalOwed_pre = loan.principalOwed();
        uint256 loanAssetLoan_pre  = IERC20(USDC).balanceOf(address(loan));
        uint256 loanAssetBorr_pre  = IERC20(USDC).balanceOf(address(ali));

        // Warp to late payment.
        hevm.warp(block.timestamp + loan.nextPaymentDue() + globals.gracePeriod() + 1);

        // Pre-state triggerDefault() checks.
        assertEq(uint256(loan.loanState()),                                                     1);
        assertEq(IERC20(collateralAsset).balanceOf(address(collateralLocker)),  collateralBalance);

        loan.triggerDefault();

        {
            uint256 principalOwed_post = loan.principalOwed();
            uint256 loanAssetLoan_post = IERC20(USDC).balanceOf(address(loan));
            uint256 loanAssetBorr_post = IERC20(USDC).balanceOf(address(ali));
            uint256 amountLiquidated   = loan.amountLiquidated();
            uint256 amountRecovered    = loan.amountRecovered();
            uint256 defaultSuffered    = loan.defaultSuffered();
            uint256 liquidationExcess  = loan.liquidationExcess();

            // Post-state triggerDefault() checks.
            assertEq(uint256(loan.loanState()),                                     4);
            assertEq(IERC20(collateralAsset).balanceOf(address(collateralLocker)),  0);
            assertEq(amountLiquidated,                              collateralBalance);

            if (amountRecovered > principalOwed_pre) {
                assertEq(loanAssetBorr_post - loanAssetBorr_pre, liquidationExcess);
                assertEq(principalOwed_post,                                     0);
                assertEq(liquidationExcess,    amountRecovered - principalOwed_pre);
                assertEq(defaultSuffered,                                        0);
                assertEq(
                    amountRecovered,                              
                    (loanAssetBorr_post - loanAssetBorr_pre) + (loanAssetLoan_post - loanAssetLoan_pre)
                );
            }
            else {
                assertEq(principalOwed_post,   principalOwed_pre - amountRecovered);
                assertEq(defaultSuffered,                       principalOwed_post);
                assertEq(liquidationExcess,                                      0);
                assertEq(amountRecovered,   loanAssetLoan_post - loanAssetLoan_pre);
            }
        }
    }

    function test_basic_liquidation() public {
        // Triangular uniswap path
        Loan wbtcLoan = createAndFundLoan(address(repaymentCalc), WBTC);
        performLiquidationAssertions(wbtcLoan);

        // Bilateral uniswap path
        Loan wethLoan = createAndFundLoan(address(repaymentCalc), WETH);
        performLiquidationAssertions(wethLoan);

        // collateralAsset == loanAsset 
        Loan usdcLoan = createAndFundLoan(address(repaymentCalc), USDC);
        performLiquidationAssertions(usdcLoan);
    }
}
