// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "./user/Borrower.sol";
import "./user/Governor.sol";
import "./user/LP.sol";
import "./user/PoolDelegate.sol";

import "../RepaymentCalc.sol";
import "../CollateralLockerFactory.sol";
import "../DebtLocker.sol";
import "../DebtLockerFactory.sol";
import "../FundingLockerFactory.sol";
import "../LateFeeCalc.sol";
import "../LiquidityLockerFactory.sol";
import "../Loan.sol";
import "../LoanFactory.sol";
import "../MapleTreasury.sol";
import "../Pool.sol";
import "../PoolFactory.sol";
import "../PremiumCalc.sol";
import "../StakeLockerFactory.sol";

import "../interfaces/IERC20Details.sol";
import "../interfaces/ILoan.sol";
import "../interfaces/IBFactory.sol";

import "../oracles/ChainlinkOracle.sol";
import "../oracles/UsdOracle.sol";

import "module/maple-token/contracts/MapleToken.sol";

contract Treasury { }

contract LoanLiquidationTest is TestUtil {

    Borrower                               ali;
    Governor                               gov;
    LP                                     bob;
    PoolDelegate                           sid;

    RepaymentCalc                repaymentCalc;
    CollateralLockerFactory          clFactory;
    DebtLockerFactory                dlFactory;
    FundingLockerFactory             flFactory;
    LateFeeCalc                    lateFeeCalc;
    LiquidityLockerFactory           llFactory;
    LoanFactory                    loanFactory;
    MapleGlobals                       globals;
    MapleToken                             mpl;
    MapleTreasury                     treasury;
    Pool                                  pool; 
    PoolFactory                    poolFactory;
    PremiumCalc                    premiumCalc;
    StakeLockerFactory               slFactory;
    ChainlinkOracle                 wethOracle;
    ChainlinkOracle                 wbtcOracle;
    UsdOracle                        usdOracle;

    IBPool                               bPool;
    IStakeLocker                   stakeLocker;

    function setUp() public {

        ali = new Borrower();     // Actor: Borrower of the Loan.
        gov = new Governor();     // Actor: Governor of Maple.
        bob = new LP();           // Actor: Individual lender.
        sid = new PoolDelegate(); // Actor: Manager of the Pool.

        mpl      = new MapleToken("MapleToken", "MAPL", USDC);
        globals  = gov.createGlobals(address(mpl));
        treasury = new MapleTreasury(address(mpl), USDC, UNISWAP_V2_ROUTER_02, address(globals));

        flFactory     = new FundingLockerFactory();         // Setup the FL factory to facilitate Loan factory functionality.
        clFactory     = new CollateralLockerFactory();      // Setup the CL factory to facilitate Loan factory functionality.
        loanFactory   = new LoanFactory(address(globals));  // Create Loan factory.
        slFactory     = new StakeLockerFactory();           // Setup the SL factory to facilitate Pool factory functionality.
        llFactory     = new LiquidityLockerFactory();       // Setup the SL factory to facilitate Pool factory functionality.
        poolFactory   = new PoolFactory(address(globals));  // Create pool factory.
        dlFactory     = new DebtLockerFactory();            // Setup DL factory to hold the cumulative funds for a loan corresponds to a pool.
        repaymentCalc = new RepaymentCalc();                // Repayment model.
        lateFeeCalc   = new LateFeeCalc(0);                 // Flat 0% fee
        premiumCalc   = new PremiumCalc(500);               // Flat 5% premium

        /*** Globals administrative actions ***/
        gov.setPoolDelegateAllowlist(address(sid), true);
        gov.setMapleTreasury(address(treasury));
        gov.setDefaultUniswapPath(WETH, USDC, USDC);
        gov.setDefaultUniswapPath(WBTC, USDC, WETH);

        /*** Validate all relevant contracts in Globals ***/
        gov.setValidLoanFactory(address(loanFactory), true);
        gov.setValidPoolFactory(address(poolFactory), true);

        gov.setValidSubFactory(address(loanFactory), address(flFactory), true);
        gov.setValidSubFactory(address(loanFactory), address(clFactory), true);

        gov.setValidSubFactory(address(poolFactory), address(llFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(slFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(dlFactory), true);

        gov.setCalc(address(repaymentCalc), true);
        gov.setCalc(address(lateFeeCalc),   true);
        gov.setCalc(address(premiumCalc),   true);
        gov.setCollateralAsset(WBTC,        true);
        gov.setCollateralAsset(WETH,        true);
        gov.setCollateralAsset(USDC,        true);
        gov.setLoanAsset(USDC,              true);

        /*** Set up oracles ***/
        wethOracle = new ChainlinkOracle(tokens["WETH"].orcl, WETH, address(this));
        wbtcOracle = new ChainlinkOracle(tokens["WBTC"].orcl, WBTC, address(this));
        usdOracle  = new UsdOracle();
        
        gov.setPriceOracle(WETH, address(wethOracle));
        gov.setPriceOracle(WBTC, address(wbtcOracle));
        gov.setPriceOracle(USDC, address(usdOracle));

        /*** Mint balances to relevant actors ***/
        mint("WETH", address(ali),         100 ether);
        mint("WBTC", address(ali),          10 * BTC);
        mint("USDC", address(bob),     100_000 * USD);
        mint("USDC", address(ali),     100_000 * USD);
        mint("USDC", address(this), 50_000_000 * USD);

        /*** Create and finalize MPL-USDC 50-50 Balancer Pool ***/
        bPool = IBPool(IBFactory(BPOOL_FACTORY).newBPool()); // Initialize MPL/USDC Balancer pool (without finalizing)

        IERC20(USDC).approve(address(bPool), MAX_UINT);
        mpl.approve(address(bPool), MAX_UINT);

        bPool.bind(USDC,         1_650_000 * USD, 5 ether);  // Bind 50m USDC with 5 denormalization weight
        bPool.bind(address(mpl),   550_000 * WAD, 5 ether);  // Bind 100k MPL with 5 denormalization weight
        bPool.finalize();
        bPool.transfer(address(sid), 100 * WAD);  // Give PD a balance of BPTs to finalize pool

        gov.setValidBalancerPool(address(bPool), true);

        /*** Create Liqiuidty Pool ***/
        pool = Pool(sid.createPool(
            address(poolFactory),
            USDC,
            address(bPool),
            address(slFactory),
            address(llFactory),
            500,
            100,
            MAX_UINT  // liquidityCap value
        ));

        /*** Pool Delegate stakes and finalizes Pool ***/ 
        stakeLocker = IStakeLocker(pool.stakeLocker());
        sid.approve(address(bPool), address(stakeLocker), 50 * WAD);
        sid.stake(address(stakeLocker), 50 * WAD);
        sid.finalize(address(pool));  // PD that staked can finalize
        sid.setOpenToPublic(address(pool), true);
        assertEq(uint256(pool.poolState()), 1);  // Finalize

        /*** LP deposits USDC into Pool ***/
        bob.approve(USDC, address(pool), MAX_UINT);
        bob.deposit(address(pool), 5000 * USD); 
    }

    function createAndFundLoan(address _interestStructure, address _collateral, uint256 collateralRatio) internal returns (Loan loan) {
        uint256[5] memory specs = [500, 90, 30, uint256(1000 * USD), collateralRatio];
        address[3] memory calcs = [_interestStructure, address(lateFeeCalc), address(premiumCalc)];

        loan = ali.createLoan(address(loanFactory), USDC, _collateral, address(flFactory), address(clFactory), specs, calcs);

        sid.fundLoan(address(pool), address(loan), address(dlFactory), 1000 * USD); 

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
        hevm.warp(block.timestamp + loan.nextPaymentDue() + globals.defaultGracePeriod() + 1);

        // Pre-state triggerDefault() checks.
        assertEq(uint256(loan.loanState()),                                                     1);
        assertEq(IERC20(collateralAsset).balanceOf(address(collateralLocker)),  collateralBalance);

        sid.triggerDefault(address(pool), address(loan), address(dlFactory));

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
        Loan wbtcLoan = createAndFundLoan(address(repaymentCalc), WBTC, 2000);
        performLiquidationAssertions(wbtcLoan);

        // Bilateral uniswap path
        Loan wethLoan = createAndFundLoan(address(repaymentCalc), WETH, 2000);
        performLiquidationAssertions(wethLoan);

        // collateralAsset == loanAsset 
        Loan usdcLoan = createAndFundLoan(address(repaymentCalc), USDC, 2000);
        performLiquidationAssertions(usdcLoan);

        // Zero collateralization
        Loan wethLoan2 = createAndFundLoan(address(repaymentCalc), WETH, 0);
        performLiquidationAssertions(wethLoan2);
    }
}
