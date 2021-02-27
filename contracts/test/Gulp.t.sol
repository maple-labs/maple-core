// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "./user/Borrower.sol";
import "./user/Governor.sol";
import "./user/LP.sol";
import "./user/PoolDelegate.sol";
import "./user/Staker.sol";

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

import "../interfaces/IBFactory.sol";
import "../interfaces/IBPool.sol";
import "../interfaces/IERC20Details.sol";
import "../interfaces/IStakeLocker.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IPoolFactory.sol";

import "../oracles/ChainlinkOracle.sol";
import "../oracles/UsdOracle.sol";

import "module/maple-token/contracts/MapleToken.sol";

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract GulpTest is TestUtil {

    using SafeMath for uint256;

    Borrower                               bob;
    Governor                               gov;
    LP                                     ali;
    PoolDelegate                           sid;
    Staker                                 che;
    Staker                                 dan;
    
    RepaymentCalc                repaymentCalc;
    CollateralLockerFactory          clFactory;
    DebtLockerFactory                dlFactory;
    FundingLockerFactory             flFactory;
    LateFeeCalc                    lateFeeCalc;
    LiquidityLockerFactory           llFactory;
    LoanFactory                    loanFactory;
    Loan                                  loan;
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

    uint256 constant public MAX_UINT = uint(-1);

    function setUp() public {

        bob            = new Borrower();                      // Actor: Borrower of the Loan.
        gov            = new Governor();                      // Actor: Governor of Maple.
        ali            = new LP();                            // Actor: Liquidity provider.
        sid            = new PoolDelegate();                  // Actor: Manager of the Pool.
        che            = new Staker();                        // Actor: Stakes BPTs in Pool.
        dan            = new Staker();                        // Actor: Staker BPTs in Pool.

        mpl            = new MapleToken("MapleToken", "MAPL", USDC);
        globals        = gov.createGlobals(address(mpl), BPOOL_FACTORY);
        treasury       = new MapleTreasury(address(mpl), USDC, UNISWAP_V2_ROUTER_02, address(globals));

        flFactory      = new FundingLockerFactory();          // Setup the FL factory to facilitate Loan factory functionality.
        clFactory      = new CollateralLockerFactory();       // Setup the CL factory to facilitate Loan factory functionality.
        loanFactory    = new LoanFactory(address(globals));   // Create Loan factory.
        slFactory      = new StakeLockerFactory();            // Setup the SL factory to facilitate Pool factory functionality.
        llFactory      = new LiquidityLockerFactory();        // Setup the SL factory to facilitate Pool factory functionality.
        poolFactory    = new PoolFactory(address(globals));   // Create pool factory.
        dlFactory      = new DebtLockerFactory();             // Setup DL factory to hold the cumulative funds for a loan corresponds to a pool.
        repaymentCalc  = new RepaymentCalc();                 // Repayment model.
        lateFeeCalc    = new LateFeeCalc(0);                  // Flat 0% fee
        premiumCalc    = new PremiumCalc(500);                // Flat 5% premium

        gov.setValidLoanFactory(address(loanFactory), true);

        gov.setValidSubFactory(address(loanFactory), address(flFactory), true);
        gov.setValidSubFactory(address(loanFactory), address(clFactory), true);

        gov.setValidSubFactory(address(poolFactory), address(llFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(slFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(dlFactory), true);

        // Mint 50m USDC into this account
        mint("USDC", address(this), 50_000_000 * USD);

        // Initialize MPL/USDC Balancer pool (without finalizing)
        bPool = IBPool(IBFactory(BPOOL_FACTORY).newBPool());

        IERC20(USDC).approve(address(bPool), MAX_UINT);
        mpl.approve(address(bPool), MAX_UINT);

        bPool.bind(USDC,         1_650_000 * USD, 5 ether);  // Bind 50m USDC with 5 denormalization weight
        bPool.bind(address(mpl),   550_000 * WAD, 5 ether);  // Bind 100k MPL with 5 denormalization weight

        assertEq(IERC20(USDC).balanceOf(address(bPool)),  1_650_000 * USD);
        assertEq(mpl.balanceOf(address(bPool)),             550_000 * WAD);

        assertEq(bPool.balanceOf(address(this)), 0);  // Not finalized

        gov.setPoolDelegateWhitelist(address(sid), true);
        gov.setMapleTreasury(address(treasury));
        bPool.finalize();

        assertEq(bPool.balanceOf(address(this)), 100 * WAD);
        assertEq(bPool.balanceOf(address(this)), bPool.INIT_POOL_SUPPLY());  // Assert BPTs were minted

        bPool.transfer(address(sid), 50 * WAD);  // Give PD a balance of BPTs to finalize pool
        bPool.transfer(address(che), 25 * WAD);  // Give staker a balance of BPTs to stake against finalized pool
        bPool.transfer(address(dan), 25 * WAD);  // Give staker a balance of BPTs to stake against finalized pool

        // Set Globals
        gov.setCalc(address(repaymentCalc), true);
        gov.setCalc(address(lateFeeCalc),   true);
        gov.setCalc(address(premiumCalc),   true);
        gov.setCollateralAsset(WETH,        true);
        gov.setLoanAsset(USDC,              true);
        gov.setSwapOutRequired(1_000_000);
        
        wethOracle = new ChainlinkOracle(tokens["WETH"].orcl, WETH, address(this));
        wbtcOracle = new ChainlinkOracle(tokens["WBTC"].orcl, WBTC, address(this));
        usdOracle  = new UsdOracle();
        
        gov.setPriceOracle(WETH, address(wethOracle));
        gov.setPriceOracle(WBTC, address(wbtcOracle));
        gov.setPriceOracle(USDC, address(usdOracle));

        
        // Create Liquidity Pool
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

        stakeLocker = IStakeLocker(pool.stakeLocker());

        // loan Specifications
        uint256[6] memory specs = [500, 180, 30, uint256(1000 * USD), 2000, 7];
        address[3] memory calcs = [address(repaymentCalc), address(lateFeeCalc), address(premiumCalc)];

        loan = bob.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);

        // Stake and finalize pool
        sid.approve(address(bPool), address(stakeLocker), 50 * WAD);
        sid.stake(address(stakeLocker), 50 * WAD);
        sid.finalize(address(pool));  // PD that staked can finalize

        assertEq(uint256(pool.poolState()), 1);  // Finalize
    }

    function setUpLoanAndDrawdown() public {
        mint("USDC", address(ali), 10_000_000 * USD);  // Mint USDC to LP
        ali.approve(USDC, address(pool), MAX_UINT);    // LP approves USDC

        ali.deposit(address(pool), 10_000_000 * USD);                                      // LP deposits 10m USDC to Pool
        sid.fundLoan(address(pool), address(loan), address(dlFactory), 10_000_000 * USD);  // PD funds loan for 10m USDC

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

        assertEq(totalFundsToken, loan.drawdownAmount() * globals.treasuryFee() / 10_000);
        assertEq(mplBal,          550_000 * WAD);
        withinPrecision(earnings, totalFundsToken * mplBal / mpl.totalSupply(), 9);

        // MPL is held by Balancer Pool, claim on behalf of BPool.
        mpl.withdrawFundsOnBehalf(address(bPool));

        uint256 usdcBal_preGulp = bPool.getBalance(USDC);

        bPool.gulp(USDC); // Update BPool with gulp(token).

        uint256 usdcBal_postGulp = bPool.getBalance(USDC);

        assertEq(usdcBal_preGulp,  1_650_000 * USD);
        assertEq(usdcBal_postGulp, usdcBal_preGulp + earnings); // USDC is transferred into balancer pool, increasing value of MPL
    }
} 
