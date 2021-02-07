
// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "./user/Borrower.sol";
import "./user/Governor.sol";
import "./user/LP.sol";
import "./user/PoolDelegate.sol";
import "./user/Staker.sol";

import "../interfaces/IBFactory.sol";
import "../interfaces/IBPool.sol";
import "../interfaces/IERC20Details.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IPoolFactory.sol";
import "../interfaces/IStakeLocker.sol";

import "../BulletRepaymentCalc.sol";
import "../DebtLocker.sol";
import "../DebtLockerFactory.sol";
import "../CollateralLockerFactory.sol";
import "../FundingLockerFactory.sol";
import "../LateFeeCalc.sol";
import "../LiquidityLockerFactory.sol";
import "../Loan.sol";
import "../LoanFactory.sol";
import "../MapleToken.sol";
import "../Pool.sol";
import "../PoolFactory.sol";
import "../PremiumCalc.sol";
import "../StakeLockerFactory.sol";

import "../mocks/value.sol";
import "../mocks/token.sol";

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract Treasury { }

contract PoolLiquidationTest is TestUtil {

    using SafeMath for uint256;

    Borrower                               che;
    Governor                               gov;
    LP                                     ali;
    LP                                     bob;
    Staker                                 dan;
    Staker                                 eli;
    PoolDelegate                           sid;
    PoolDelegate                           joe;

    BulletRepaymentCalc             bulletCalc;
    CollateralLockerFactory          clFactory;
    DebtLockerFactory                dlFactory;
    FundingLockerFactory             flFactory;
    LateFeeCalc                    lateFeeCalc;
    LiquidityLockerFactory           llFactory;
    LoanFactory                    loanFactory;
    Loan                                  loan;
    MapleGlobals                       globals;
    MapleToken                             mpl;
    PoolFactory                    poolFactory;
    StakeLockerFactory               slFactory; 
    Pool                                pool_a;  
    Pool                                pool_b; 
    PremiumCalc                    premiumCalc;
    Treasury                               trs;

    IBPool                               bPool;
    IStakeLocker                 stakeLocker_a;
    IStakeLocker                 stakeLocker_b;

    uint256 constant public MAX_UINT = uint(-1);

    function setUp() public {

        che            = new Borrower();                     // Actor: Borrower of the Loan.
        gov            = new Governor();                     // Actor: Governor of Maple.
        sid            = new PoolDelegate();                 // Actor: Manager of the pool_a.
        joe            = new PoolDelegate();                 // Actor: Manager of the pool_b.
        ali            = new LP();                           // Actor: Liquidity provider.
        bob            = new LP();                           // Actor: Liquidity provider.
        dan            = new Staker();                       // Actor: Stakes BPTs in Pool.
        eli            = new Staker();                       // Actor: Stakes BPTs in Pool.

        mpl            = new MapleToken("MapleToken", "MAPL", USDC);
        globals        = gov.createGlobals(address(mpl), BPOOL_FACTORY);
        flFactory      = new FundingLockerFactory();         // Setup the FL factory to facilitate Loan factory functionality.
        clFactory      = new CollateralLockerFactory();      // Setup the CL factory to facilitate Loan factory functionality.
        loanFactory    = new LoanFactory(address(globals));  // Create Loan factory.
        slFactory      = new StakeLockerFactory();           // Setup the SL factory to facilitate Pool factory functionality.
        llFactory      = new LiquidityLockerFactory();       // Setup the SL factory to facilitate Pool factory functionality.
        poolFactory    = new PoolFactory(address(globals));  // Create pool factory.
        dlFactory      = new DebtLockerFactory();            // Setup DL factory to hold the cumulative funds for a loan corresponds to a pool.
        bulletCalc     = new BulletRepaymentCalc();          // Repayment model.
        lateFeeCalc    = new LateFeeCalc(0);                 // Flat 0% fee
        premiumCalc    = new PremiumCalc(500);               // Flat 5% premium
        trs            = new Treasury();                     // Treasury.

        gov.setValidLoanFactory(address(loanFactory), true);

        gov.setValidSubFactory(address(loanFactory), address(flFactory), true);
        gov.setValidSubFactory(address(loanFactory), address(clFactory), true);

        gov.setValidSubFactory(address(poolFactory), address(llFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(slFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(dlFactory), true);
        
        gov.setPriceOracle(WETH, 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
        gov.setPriceOracle(WBTC, 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c);
        gov.setPriceOracle(USDC, 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9);

        gov.setDefaultUniswapPath(WETH, USDC, USDC);
        gov.setDefaultUniswapPath(WBTC, USDC, WETH);

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

        gov.setPoolDelegateWhitelist(address(sid), true);
        gov.setPoolDelegateWhitelist(address(joe), true);
        gov.setMapleTreasury(address(trs));
        bPool.finalize();

        assertEq(bPool.balanceOf(address(this)), 100 * WAD);
        assertEq(bPool.balanceOf(address(this)), bPool.INIT_POOL_SUPPLY());  // Assert BPTs were minted TODO: Find a way to mint more than 100 BPTs

        bPool.transfer(address(sid), 25 * WAD);  // Give PD a balance of BPTs to finalize pool
        bPool.transfer(address(joe), 25 * WAD);  // Give PD a balance of BPTs to finalize pool
        bPool.transfer(address(che), 25 * WAD);  // Give staker a balance of BPTs to stake against finalized pool
        bPool.transfer(address(dan), 25 * WAD);  // Give staker a balance of BPTs to stake against finalized pool

        // Set Globals
        gov.setCalc(address(bulletCalc),  true);
        gov.setCalc(address(lateFeeCalc), true);
        gov.setCalc(address(premiumCalc), true);
        gov.setCollateralAsset(WETH, true);
        gov.setLoanAsset(USDC, true);
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

        // Create Liquidity Pool B
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
        address[3] memory calcs = [address(bulletCalc), address(lateFeeCalc), address(premiumCalc)];

        loan = che.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);

        // Stake and finalize pool
        sid.approve(address(bPool), address(stakeLocker_a), 25 * WAD);
        joe.approve(address(bPool), address(stakeLocker_b), 25 * WAD);
        sid.stake(address(stakeLocker_a), 10 * WAD);  // Less than 1/6, so that all BPTs can be burned in tests
        joe.stake(address(stakeLocker_b), 25 * WAD);
        sid.finalize(address(pool_a));
        joe.finalize(address(pool_b));

        assertEq(uint256(pool_a.poolState()), 1);  // Finalize
        assertEq(uint256(pool_b.poolState()), 1);  // Finalize
    }

    function setUpLoanAndDefault() public {
        // Fund the pool
        mint("USDC", address(ali), 20_000_000 * USD);
        ali.approve(USDC, address(pool_a), MAX_UINT);
        ali.approve(USDC, address(pool_b), MAX_UINT);
        ali.deposit(address(pool_a), 10_000_000 * USD);
        ali.deposit(address(pool_b), 10_000_000 * USD);

        // Fund the loan
        sid.fundLoan(address(pool_a), address(loan), address(dlFactory), 1_000_000 * USD);
        joe.fundLoan(address(pool_b), address(loan), address(dlFactory), 3_000_000 * USD);
        uint cReq = loan.collateralRequiredForDrawdown(4_000_000 * USD);

        // Drawdown loan
        mint("WETH", address(che), cReq);
        che.approve(WETH, address(loan), MAX_UINT);
        che.drawdown(address(loan), 4_000_000 * USD);
        
        // Warp to late payment
        uint256 start = block.timestamp;
        uint256 nextPaymentDue = loan.nextPaymentDue();
        uint256 gracePeriod = globals.gracePeriod();
        hevm.warp(start + nextPaymentDue + gracePeriod + 1);

        // Trigger default
        loan.triggerDefault();
    }

    function test_claim_default_info() public {

        setUpLoanAndDefault();

        /**
            Now that triggerDefault() is called, the return value defaultSuffered
            will be greater than 0. Calling claim() is the mechanism which settles,
            or rather updates accounting in the Pool which in turn will enable us
            to handle liquidation of BPTs in the Stake Locker accurately.
        */
        uint256[7] memory vals_a = sid.claim(address(pool_a), address(loan),  address(dlFactory));
        uint256[7] memory vals_b = joe.claim(address(pool_b), address(loan),  address(dlFactory));

        // Non-zero value is passed through.
        assertEq(vals_a[6], loan.defaultSuffered() * (1_000_000 * WAD) / (4_000_000 * WAD));
        assertEq(vals_b[6], loan.defaultSuffered() * (3_000_000 * WAD) / (4_000_000 * WAD));
        withinPrecision(vals_a[6] + vals_b[6], loan.defaultSuffered(), 2);
    }

    function test_claim_default_burn_BPT_full_recover() public {

        setUpLoanAndDefault();

        address liquidityLocker_a = pool_a.liquidityLocker();
        address liquidityLocker_b = pool_b.liquidityLocker();

        // Pre-state liquidityLocker checks.
        uint256 liquidityLockerBal_pre_a = IERC20(USDC).balanceOf(liquidityLocker_a);
        uint256 liquidityLockerBal_pre_b = IERC20(USDC).balanceOf(liquidityLocker_b);

        uint256 principalOut_pre_a = pool_a.principalOut();
        uint256 principalOut_pre_b = pool_b.principalOut();

        sid.claim(address(pool_a), address(loan),  address(dlFactory));
        joe.claim(address(pool_b), address(loan),  address(dlFactory));

        // Post-state liquidityLocker checks.
        uint256 liquidityLockerBal_post_a = IERC20(USDC).balanceOf(liquidityLocker_a);
        uint256 liquidityLockerBal_post_b = IERC20(USDC).balanceOf(liquidityLocker_b);

        uint256 principalOut_post_a = pool_a.principalOut();
        uint256 principalOut_post_b = pool_b.principalOut();

        assertEq(principalOut_pre_a, 1_000_000 * USD);
        assertEq(principalOut_pre_b, 3_000_000 * USD);

        assertEq(liquidityLockerBal_pre_a, 9_000_000 * USD);
        assertEq(liquidityLockerBal_pre_b, 7_000_000 * USD);
        
        withinDiff(liquidityLockerBal_post_a - liquidityLockerBal_pre_a, 1_000_000 * USD, 1);  // Entire initial loan amount was recovered between liquidation and burn
        withinDiff(liquidityLockerBal_post_b - liquidityLockerBal_pre_b, 3_000_000 * USD, 1);  // Entire initial loan amount was recovered between liquidation and burn

        withinDiff(principalOut_post_a, 0, 1);  // Principal out is set to zero (with dust)
        withinDiff(principalOut_post_b, 0, 1);  // Principal out is set to zero (with dust)

        assertEq(liquidityLockerBal_pre_a  + principalOut_pre_a,  10_000_000 * USD);  // Total pool value = 9m + 1m = 10m
        assertEq(liquidityLockerBal_post_a + principalOut_post_a, 10_000_000 * USD);  // Total pool value = 10m + 0 = 10m (successful full coverage from liquidation + staker burn)

        assertEq(liquidityLockerBal_pre_b  + principalOut_pre_b,  10_000_000 * USD);  // Total pool value = 7m + 3m = 10m
        assertEq(liquidityLockerBal_post_b + principalOut_post_b, 10_000_000 * USD);  // Total pool value = 1m + 0 = 10m (successful full coverage from liquidation + staker burn)
    }

    function test_claim_default_burn_BPT_shortfall() public {

        // Fund the pool
        mint("USDC", address(ali), 500_000_000 * USD);
        mint("USDC", address(bob),  10_000_000 * USD);

        ali.approve(USDC, address(pool_a), MAX_UINT);
        bob.approve(USDC, address(pool_a), MAX_UINT);
        ali.deposit(address(pool_a), 500_000_000 * USD);  // Ali symbolizes all other LPs, test focuses on Bob
        bob.deposit(address(pool_a), 10_000_000 * USD);

        sid.setPenaltyDelay(address(pool_a), 0);  // So Bob can withdraw without penalty

        // TPV = LL + PO = 510 + 0

        // Fund the loan
        sid.fundLoan(address(pool_a), address(loan), address(dlFactory), 100_000_000 * USD);
        uint cReq = loan.collateralRequiredForDrawdown(100_000_000 * USD);

        // TPV = LL + PO = 410 + 100 = 510

        // Drawdown loan
        mint("WETH", address(che), cReq);
        che.approve(WETH, address(loan), MAX_UINT);
        che.drawdown(address(loan), 100_000_000 * USD);
        
        // Warp to late payment
        uint256 start = block.timestamp;
        uint256 nextPaymentDue = loan.nextPaymentDue();
        uint256 gracePeriod = globals.gracePeriod();
        hevm.warp(start + nextPaymentDue + gracePeriod + 1);

        // Trigger default
        loan.triggerDefault();

        // TPV = LL + PO = 410 + 100 = 510

        address liquidityLocker = pool_a.liquidityLocker();
        address stakeLocker     = pool_a.stakeLocker();

        // Pre-state liquidityLocker checks.
        uint256 liquidityLockerBal_pre = IERC20(USDC).balanceOf(liquidityLocker);
        uint256 slBPTBal_pre           = bPool.balanceOf(stakeLocker);
        uint256 principalOut_pre       = pool_a.principalOut();
        uint256 bptShortfall_pre       = pool_a.bptShortfall();

        // LLBalance
        // principalOut
        // BPT bal of stakeLocker
        // bptShortfall

        uint256[7] memory vals_a = sid.claim(address(pool_a), address(loan),  address(dlFactory));

        // TPV = LL + PO - shortfall

        uint256 liquidityLockerBal_post = IERC20(USDC).balanceOf(liquidityLocker);
        uint256 slBPTBal_post           = bPool.balanceOf(stakeLocker);
        uint256 principalOut_post       = pool_a.principalOut();
        uint256 bptShortfall_post       = pool_a.bptShortfall();

        assertEq(liquidityLockerBal_pre,  1);
        assertEq(liquidityLockerBal_post, 2);
        assertEq(slBPTBal_pre,            3);
        assertEq(slBPTBal_post,           4);
        assertEq(principalOut_pre,        5);
        assertEq(principalOut_post,       6);
        assertEq(bptShortfall_pre,        7);
        assertEq(bptShortfall_post,       8);

        assertEq(principalOut_pre,       1_000_000 * USD);
        assertEq(liquidityLockerBal_pre, 9_000_000 * USD);

        assertEq(slBPTBal_pre,  10 * WAD);
        assertLt(slBPTBal_post,     1E10); // Dusty stakeLocker BPT return bal (less than 1e-8 WAD), meaning essentially all BPTs were burned

        assertEq(bptShortfall_pre,                 0);  // No bptShortfall before bpt burning occurs
        assertGt(bptShortfall_post, 40_000_000 * USD);  // Over $40m in shortfall after liquidation and BPT burn

        assertEq(liquidityLockerBal_pre  + principalOut_pre,                      510_000_000 * USD);
        assertEq(liquidityLockerBal_post + principalOut_post + bptShortfall_post, 510_000_000 * USD); // LLBal + PO goes down, bptShortfall distributes that loss

        withinDiff(principalOut_post, 0, 1);  // Principal out is set to zero (with dust)

        uint256 bob_recognizeableLosses = pool_a.recognizeableLossesOf(address(bob));

        assertTrue(!bob.try_withdraw(address(pool_a), bob_recognizeableLosses - 1));  // Cannot withdraw less than recognizeableLosses

        uint bob_usdcBal_pre = IERC20(USDC).balanceOf(address(bob));
        uint bob_poolBal_pre = pool_a.balanceOf(address(bob));

        assertTrue(bob.try_withdraw(address(pool_a), bob_recognizeableLosses));

        uint bob_usdcBal_post = IERC20(USDC).balanceOf(address(bob));
        uint bob_poolBal_post = pool_a.balanceOf(address(bob));

        liquidityLockerBal_pre  = liquidityLockerBal_post;
        liquidityLockerBal_post = IERC20(USDC).balanceOf(liquidityLocker);

        bptShortfall_pre  = bptShortfall_post;
        bptShortfall_post = pool_a.bptShortfall();

        assertEq(bob_usdcBal_post - bob_usdcBal_pre,                         0);  // Bob's USDC value withdrawn did not increase
        assertEq(bob_poolBal_pre  - bob_poolBal_post,  bob_recognizeableLosses);  // Bob's FDTs have been burned
        assertEq(bptShortfall_pre - bptShortfall_post, bob_recognizeableLosses);  // BPT shortfall accounting has been decremented by Bob's recognized losses

        assertEq(liquidityLockerBal_pre - liquidityLockerBal_post, bob_recognizeableLosses);

        // assertEq(bob_beforeBal,       9);
        // assertEq(bob_afterBal,       10);

        // assertEq(bob_afterBal - bob_beforeBal, 1);
        // assertGt(vals_a[5], 0);

        assertTrue(false);
      
    }
} 


// function exitswapExternAmountOut(address tokenOut, uint tokenAmountOut, uint maxPoolAmountIn)
//         external
//         _logs_
//         _lock_
//         returns (uint poolAmountIn)
//     {
//         require(_finalized, "ERR_NOT_FINALIZED");
//         require(_records[tokenOut].bound, "ERR_NOT_BOUND");
//         require(tokenAmountOut <= bmul(_records[tokenOut].balance, MAX_OUT_RATIO), "ERR_MAX_OUT_RATIO");

//         Record storage outRecord = _records[tokenOut];

//         poolAmountIn = calcPoolInGivenSingleOut(
//                             outRecord.balance,
//                             outRecord.denorm,
//                             _totalSupply,
//                             _totalWeight,
//                             tokenAmountOut,
//                             _swapFee
//                         );

//         require(poolAmountIn != 0, "ERR_MATH_APPROX");
//         require(poolAmountIn <= maxPoolAmountIn, "ERR_LIMIT_IN");

//         outRecord.balance = bsub(outRecord.balance, tokenAmountOut);

//         uint exitFee = bmul(poolAmountIn, EXIT_FEE);

//         emit LOG_EXIT(msg.sender, tokenOut, tokenAmountOut);

//         _pullPoolShare(msg.sender, poolAmountIn);
//         _burnPoolShare(bsub(poolAmountIn, exitFee));
//         _pushPoolShare(_factory, exitFee);
//         _pushUnderlying(tokenOut, msg.sender, tokenAmountOut);        

//         return poolAmountIn;
//     }
