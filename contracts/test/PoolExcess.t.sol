// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "./user/Borrower.sol";
import "./user/Governor.sol";
import "./user/LP.sol";
import "./user/Staker.sol";
import "./user/PoolDelegate.sol";

import "../interfaces/IBFactory.sol";
import "../interfaces/IBPool.sol";
import "../interfaces/IERC20Details.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IPoolFactory.sol";
import "../interfaces/IStakeLocker.sol";

import "../RepaymentCalc.sol";
import "../CollateralLockerFactory.sol";
import "../DebtLockerFactory.sol";
import "../DebtLocker.sol";
import "../FundingLockerFactory.sol";
import "../LateFeeCalc.sol";
import "../Loan.sol";
import "../LoanFactory.sol";
import "../LiquidityLockerFactory.sol";
import "../Pool.sol";
import "../PoolFactory.sol";
import "../PremiumCalc.sol";
import "../StakeLockerFactory.sol";

import "../oracles/ChainlinkOracle.sol";
import "../oracles/UsdOracle.sol";

import "module/maple-token/contracts/MapleToken.sol";

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract Treasury { }

contract PoolExcessTest is TestUtil {

    using SafeMath for uint256;

    Borrower                               bob;
    Governor                               gov;
    LP                                     ali;
    PoolDelegate                           sid;
    PoolDelegate                           joe;
    Staker                                 che;
    Staker                                 dan;

    RepaymentCalc                repaymentCalc;
    CollateralLockerFactory          clFactory;
    DebtLockerFactory                dlFactory;
    FundingLockerFactory             flFactory;
    LateFeeCalc                    lateFeeCalc;
    Loan                                  loan;
    LoanFactory                    loanFactory;
    LiquidityLockerFactory           llFactory;
    MapleToken                             mpl;
    MapleGlobals                       globals;
    Pool                                pool_a;
    Pool                                pool_b;
    PoolFactory                    poolFactory;
    PremiumCalc                    premiumCalc;
    StakeLockerFactory               slFactory;
    Treasury                               trs;
    ChainlinkOracle                 wethOracle;
    ChainlinkOracle                 wbtcOracle;
    UsdOracle                        usdOracle;

    IBPool                               bPool;
    IStakeLocker                 stakeLocker_a;
    IStakeLocker                 stakeLocker_b;

    function setUp() public {

        bob            = new Borrower();                     // Actor: Borrower of the Loan.
        gov            = new Governor();                     // Actor: Governor of Maple.
        ali            = new LP();                           // Actor: Liquidity provider.
        sid            = new PoolDelegate();                 // Actor: Manager of pool_a.
        joe            = new PoolDelegate();                 // Actor: Manager of pool_b.
        che            = new Staker();                       // Actor: Stakes BPTs in Pool.
        dan            = new Staker();                       // Actor: Stakes BPTs in Pool.

        mpl            = new MapleToken("MapleToken", "MAPL", USDC);
        globals        = gov.createGlobals(address(mpl), BPOOL_FACTORY);
        flFactory      = new FundingLockerFactory();         // Setup the FL factory to facilitate Loan factory functionality.
        clFactory      = new CollateralLockerFactory();      // Setup the CL factory to facilitate Loan factory functionality.
        loanFactory    = new LoanFactory(address(globals));  // Create Loan factory.
        slFactory      = new StakeLockerFactory();           // Setup the SL factory to facilitate Pool factory functionality.
        llFactory      = new LiquidityLockerFactory();       // Setup the SL factory to facilitate Pool factory functionality.
        poolFactory    = new PoolFactory(address(globals));  // Create pool factory.
        dlFactory      = new DebtLockerFactory();            // Setup DL factory to hold the cumulative funds for a loan corresponds to a pool.
        repaymentCalc  = new RepaymentCalc();                // Repayment model.
        lateFeeCalc    = new LateFeeCalc(0);                 // Flat 0% fee
        premiumCalc    = new PremiumCalc(500);               // Flat 5% premium
        trs            = new Treasury();                     // Treasury.

        gov.setValidLoanFactory(address(loanFactory), true);
        gov.setValidPoolFactory(address(poolFactory), true);

        gov.setValidSubFactory(address(loanFactory), address(flFactory), true);
        gov.setValidSubFactory(address(loanFactory), address(clFactory), true);

        gov.setValidSubFactory(address(poolFactory), address(llFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(slFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(dlFactory), true);

        wethOracle = new ChainlinkOracle(tokens["WETH"].orcl, WETH, address(this));
        wbtcOracle = new ChainlinkOracle(tokens["WBTC"].orcl, WBTC, address(this));
        usdOracle  = new UsdOracle();
        
        gov.setPriceOracle(WETH, address(wethOracle));
        gov.setPriceOracle(WBTC, address(wbtcOracle));
        gov.setPriceOracle(USDC, address(usdOracle));

        // Mint 50m USDC into this account
        mint("USDC", address(this), 50_000_000 * USD);

        // Initialize MPL/USDC Balancer pool (without finalizing)
        bPool = IBPool(IBFactory(BPOOL_FACTORY).newBPool());

        IERC20(USDC).approve(address(bPool), MAX_UINT);
        mpl.approve(address(bPool), MAX_UINT);

        bPool.bind(USDC, 50_000_000 * USD, 5 ether);       // Bind 50m USDC with 5 denormalization weight
        bPool.bind(address(mpl), 100_000 * WAD, 5 ether);  // Bind 100k MPL with 5 denormalization weight

        assertEq(IERC20(USDC).balanceOf(address(bPool)), 50_000_000 * USD);
        assertEq(mpl.balanceOf(address(bPool)),             100_000 * WAD);

        assertEq(bPool.balanceOf(address(this)), 0);  // Not finalized

        gov.setPoolDelegateAllowlist(address(sid), true);
        gov.setPoolDelegateAllowlist(address(joe), true);
        gov.setMapleTreasury(address(trs));
        bPool.finalize();

        assertEq(bPool.balanceOf(address(this)), 100 * WAD);
        assertEq(bPool.balanceOf(address(this)), bPool.INIT_POOL_SUPPLY());  // Assert BPTs were minted

        bPool.transfer(address(sid), 25 * WAD);  // Give PD a balance of BPTs to finalize pool
        bPool.transfer(address(joe), 25 * WAD);  // Give PD a balance of BPTs to finalize pool
        bPool.transfer(address(che), 25 * WAD);  // Give staker a balance of BPTs to stake against finalized pool
        bPool.transfer(address(dan), 25 * WAD);  // Give staker a balance of BPTs to stake against finalized pool

        gov.setValidBalancerPool(address(bPool), true);

        // Set Globals
        gov.setCalc(address(repaymentCalc), true);
        gov.setCalc(address(lateFeeCalc),   true);
        gov.setCalc(address(premiumCalc),   true);
        gov.setCollateralAsset(WETH,        true);
        gov.setLoanAsset(USDC,              true);
        gov.setSwapOutRequired(1_000_000);

        // Create Liquidity Pool A
        pool_a = Pool(sid.createPool(
            address(poolFactory),
            USDC,
            address(bPool),
            address(slFactory),
            address(llFactory),
            500,
            100,
            MAX_UINT  // liquidityCap value
        ));

        // Create Liquidity Pool
        pool_b = Pool(joe.createPool(
            address(poolFactory),
            USDC,
            address(bPool),
            address(slFactory),
            address(llFactory),
            500,
            100,
            MAX_UINT  // liquidityCap value
        ));

        stakeLocker_a = IStakeLocker(pool_a.stakeLocker());
        stakeLocker_b = IStakeLocker(pool_b.stakeLocker());

        // loan Specifications
        uint256[6] memory specs = [500, 180, 30, uint256(1000 * USD), 2000, 7];
        address[3] memory calcs = [address(repaymentCalc), address(lateFeeCalc), address(premiumCalc)];

        loan = bob.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);

        // Stake and finalize pool
        sid.approve(address(bPool), address(stakeLocker_a), 25 * WAD);
        joe.approve(address(bPool), address(stakeLocker_b), 25 * WAD);
        sid.stake(address(stakeLocker_a), 25 * WAD);
        joe.stake(address(stakeLocker_b), 25 * WAD);
        sid.finalize(address(pool_a));
        joe.finalize(address(pool_b));
        sid.setOpenToPublic(address(pool_a), true);
        joe.setOpenToPublic(address(pool_b), true);

        assertEq(uint256(pool_a.poolState()), 1);  // Finalize
        assertEq(uint256(pool_b.poolState()), 1);  // Finalize
    }

    function setUpLoan() public {
        // Fund the pool
        mint("USDC", address(ali), 20_000_000 * USD);
        ali.approve(USDC, address(pool_a), MAX_UINT);
        ali.approve(USDC, address(pool_b), MAX_UINT);
        ali.deposit(address(pool_a), 10_000_000 * USD);
        ali.deposit(address(pool_b), 10_000_000 * USD);

        // Fund the loan
        sid.fundLoan(address(pool_a), address(loan), address(dlFactory), 1_000_000 * USD);
        joe.fundLoan(address(pool_b), address(loan), address(dlFactory), 3_000_000 * USD);
    }

    function test_unwind_loan_reclaim() public {

        setUpLoan();

        // Warp and call unwind()
        hevm.warp(loan.createdAt() + globals.drawdownGracePeriod() + 1);
        assertTrue(bob.try_unwind(address(loan)));

        uint256 principalOut_a_pre = pool_a.principalOut();
        uint256 principalOut_b_pre = pool_b.principalOut();
        uint256 llBalance_a_pre = IERC20(pool_a.liquidityAsset()).balanceOf(pool_a.liquidityLocker());
        uint256 llBalance_b_pre = IERC20(pool_b.liquidityAsset()).balanceOf(pool_b.liquidityLocker());

        // Claim unwind() excessReturned
        uint256[7] memory vals_a = sid.claim(address(pool_a), address(loan),  address(dlFactory));
        uint256[7] memory vals_b = joe.claim(address(pool_b), address(loan),  address(dlFactory));

        uint256 principalOut_a_post = pool_a.principalOut();
        uint256 principalOut_b_post = pool_b.principalOut();
        uint256 llBalance_a_post = IERC20(pool_a.liquidityAsset()).balanceOf(pool_a.liquidityLocker());
        uint256 llBalance_b_post = IERC20(pool_b.liquidityAsset()).balanceOf(pool_b.liquidityLocker());

        assertEq(principalOut_a_pre - principalOut_a_post, vals_a[4]);   
        assertEq(principalOut_b_pre - principalOut_b_post, vals_b[4]);
        assertEq(llBalance_a_post - llBalance_a_pre, vals_a[4]);   
        assertEq(llBalance_b_post - llBalance_b_pre, vals_b[4]);

        // pool_a invested 1mm USD
        // pool_b invested 3mm USD
        withinDiff(principalOut_a_pre - principalOut_a_post, 1_000_000 * USD, 1);
        withinDiff(principalOut_b_pre - principalOut_b_post, 3_000_000 * USD, 1);
    }
} 
