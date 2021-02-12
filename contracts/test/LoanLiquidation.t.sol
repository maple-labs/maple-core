// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "./user/Borrower.sol";
import "./user/Governor.sol";
import "./user/Lender.sol";

import "../BulletRepaymentCalc.sol";
import "../CollateralLockerFactory.sol";
import "../FundingLockerFactory.sol";
import "../LateFeeCalc.sol";
import "../LoanFactory.sol";
import "../MapleGlobals.sol";
import "../MapleToken.sol";
import "../PremiumCalc.sol";

import "../oracles/ChainLinkOracle.sol";

import "../interfaces/IERC20Details.sol";
import "../interfaces/ILoan.sol";

contract Treasury { }

contract LoanLiquidationTest is TestUtil {

    Borrower                         ali;
    Governor                         gov;
    Lender                           bob;

    BulletRepaymentCalc       bulletCalc;
    CollateralLockerFactory    clFactory;
    FundingLockerFactory       flFactory;
    LateFeeCalc              lateFeeCalc;
    LoanFactory              loanFactory;
    MapleToken                       mpl;
    MapleGlobals                 globals;
    PremiumCalc              premiumCalc;
    Treasury                         trs;
    ChainLinkOracle           wETHOracle;
    ChainLinkOracle           wBTCOracle;
    ChainLinkOracle            uSDOracle;

    ERC20                     fundsToken;

    function setUp() public {

        ali         = new Borrower();   // Actor: Borrower of the Loan.
        gov         = new Governor();   // Actor: Governor of Maple.
        bob         = new Lender();     // Actor: Individual lender.

        mpl         = new MapleToken("MapleToken", "MAPL", USDC);
        globals     = gov.createGlobals(address(mpl), BPOOL_FACTORY);  // Setup Maple Globals.
        flFactory   = new FundingLockerFactory();
        clFactory   = new CollateralLockerFactory();
        bulletCalc  = new BulletRepaymentCalc();
        lateFeeCalc = new LateFeeCalc(0);   // Flat 0% fee
        premiumCalc = new PremiumCalc(500); // Flat 5% premium
        loanFactory = new LoanFactory(address(globals));
        trs         = new Treasury();


        gov.setCalc(address(bulletCalc),  true);
        gov.setCalc(address(lateFeeCalc), true);
        gov.setCalc(address(premiumCalc), true);
        gov.setCollateralAsset(WETH,      true);
        gov.setCollateralAsset(WBTC,      true);
        gov.setLoanAsset(USDC,            true);
        
        wETHOracle = new ChainLinkOracle(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419, WETH, address(this));
        wBTCOracle = new ChainLinkOracle(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c, WBTC, address(this));
        uSDOracle  = new ChainLinkOracle(0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9, USDC, address(this));
        
        gov.setPriceOracle(WETH, address(wETHOracle));
        gov.setPriceOracle(WBTC, address(wBTCOracle));
        gov.setPriceOracle(USDC, address(uSDOracle));

        gov.setValidSubFactory(address(loanFactory), address(flFactory), true);
        gov.setValidSubFactory(address(loanFactory), address(clFactory), true);

        gov.setDefaultUniswapPath(WETH, USDC, USDC);
        gov.setDefaultUniswapPath(WBTC, USDC, WETH);
        gov.setMapleTreasury(address(trs));

        mint("WETH", address(ali),   100 ether);
        mint("WBTC", address(ali),    10 * BTC);
        mint("USDC", address(bob), 10000 * USD);
        mint("USDC", address(ali),   500 * USD);
    }

    function createAndFundLoan(address _interestStructure, address _collateral) internal returns (Loan loan) {
        uint256[6] memory specs = [500, 90, 30, uint256(1000 * USD), 2000, 7];
        address[3] memory calcs = [_interestStructure, address(lateFeeCalc), address(premiumCalc)];

        loan = ali.createLoan(address(loanFactory), USDC, _collateral, address(flFactory), address(clFactory), specs, calcs);

        bob.approve(USDC, address(loan), 5000 * USD);

        bob.fundLoan(address(loan), 5000 * USD, address(ali));
        ali.approve(_collateral, address(loan), 0.4 ether);
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

        {
            // Fetch time variables.
            uint256 start          = block.timestamp;
            uint256 nextPaymentDue = loan.nextPaymentDue();
            uint256 gracePeriod    = globals.gracePeriod();

            // Warp to late payment.
            hevm.warp(start + nextPaymentDue + gracePeriod + 1);
        }

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
        Loan wbtcLoan = createAndFundLoan(address(bulletCalc), WBTC);
        performLiquidationAssertions(wbtcLoan);

        // Bilateral uniswap path
        Loan wethLoan = createAndFundLoan(address(bulletCalc), WETH);
        performLiquidationAssertions(wethLoan);
    }
}
