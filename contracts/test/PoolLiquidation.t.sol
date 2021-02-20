
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

import "../RepaymentCalc.sol";
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

import "../oracles/ChainlinkOracle.sol";
import "../oracles/UsdOracle.sol";

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

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
    PoolFactory                    poolFactory;
    StakeLockerFactory               slFactory; 
    Pool                                pool_a;  
    Pool                                pool_b; 
    PremiumCalc                    premiumCalc;
    Treasury                               trs;
    ChainlinkOracle                 wethOracle;
    ChainlinkOracle                 wbtcOracle;
    UsdOracle                        usdOracle;

    IBPool                               bPool;
    IStakeLocker                 stakeLocker_a;
    IStakeLocker                 stakeLocker_b;

    uint256 constant public MAX_UINT = uint(-1);

    struct TestObj {
        uint256 pre;
        uint256 post;
    }

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
        repaymentCalc  = new RepaymentCalc();                // Repayment model.
        lateFeeCalc    = new LateFeeCalc(0);                 // Flat 0% fee
        premiumCalc    = new PremiumCalc(500);               // Flat 5% premium
        trs            = new Treasury();                     // Treasury.

        gov.setValidLoanFactory(address(loanFactory), true);

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

        gov.setDefaultUniswapPath(WETH, USDC, USDC);
        gov.setDefaultUniswapPath(WBTC, USDC, WETH);

        gov.setMaxSwapSlippage(2000);  // Set to 20% for the sake of the BPT shortfall test, TODO: address this when using launch params

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
        address[3] memory calcs = [address(repaymentCalc), address(lateFeeCalc), address(premiumCalc)];

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

    function assertPoolAccounting(Pool pool) internal {
        uint256 liquidityAssetDecimals = IERC20Details(address(pool.liquidityAsset())).decimals();

        uint256 liquidityLockerBal = pool.liquidityAsset().balanceOf(pool.liquidityLocker());
        uint256 fdtTotalSupply     = pool.totalSupply().mul(10 ** liquidityAssetDecimals).div(WAD);  // Convert to liquidityAsset precision
        uint256 principalOut       = pool.principalOut();
        uint256 interestSum        = pool.interestSum();
        uint256 bptShortfall       = pool.bptShortfall();

        // Total Pool Value = LLBal + PO = fdtSupply + interestSum + aggregate unrecognized losses
        assertEq(liquidityLockerBal + principalOut, fdtTotalSupply + interestSum - bptShortfall, "Pool accounting compromised");
    }

    function test_claim_default_burn_BPT_shortfall() public {

        {
            // Fund the pool
            mint("USDC", address(ali), 500_000_000 * USD);
            mint("USDC", address(bob),  10_000_000 * USD);

            ali.approve(USDC, address(pool_a), MAX_UINT);
            bob.approve(USDC, address(pool_a), MAX_UINT);
            ali.deposit(address(pool_a), 500_000_000 * USD);  // Ali symbolizes all other LPs, test focuses on Bob
            bob.deposit(address(pool_a), 10_000_000 * USD);

            assertPoolAccounting(pool_a);

            sid.setPenaltyDelay(address(pool_a), 0);  // So Bob can withdraw without penalty

            // Fund the loan
            sid.fundLoan(address(pool_a), address(loan), address(dlFactory), 100_000_000 * USD);
            uint cReq = loan.collateralRequiredForDrawdown(100_000_000 * USD);

            assertPoolAccounting(pool_a);

            // Drawdown loan
            mint("WETH", address(che), cReq);
            che.approve(WETH, address(loan), MAX_UINT);
            che.drawdown(address(loan), 100_000_000 * USD);

            assertPoolAccounting(pool_a);
        }

        // Warp to late payment
        hevm.warp(block.timestamp + loan.nextPaymentDue() + globals.gracePeriod() + 1);

        // Trigger default
        loan.triggerDefault();

        // Instantiate all test variables
        TestObj memory liquidityLockerBal;
        TestObj memory slBPTBal;
        TestObj memory fdtSupply;
        TestObj memory principalOut;
        TestObj memory bptShortfall;
        TestObj memory bob_usdcBal;
        TestObj memory bob_poolBal;
        TestObj memory bob_recognizeableLosses;

        address liquidityLocker = pool_a.liquidityLocker();
        address stakeLocker     = pool_a.stakeLocker();

        /**************************************************/
        /*** Loan Default Accounting with BPT Shortfall ***/
        /**************************************************/

        // Pre-claim accounting checks
        liquidityLockerBal.pre = IERC20(USDC).balanceOf(liquidityLocker);
        slBPTBal.pre           = bPool.balanceOf(stakeLocker);
        fdtSupply.pre          = pool_a.totalSupply();
        principalOut.pre       = pool_a.principalOut();
        bptShortfall.pre       = pool_a.bptShortfall();

        uint256[7] memory vals_a = sid.claim(address(pool_a), address(loan),  address(dlFactory));

        assertPoolAccounting(pool_a);

        // Pre-claim accounting checks
        liquidityLockerBal.post = IERC20(USDC).balanceOf(liquidityLocker);
        slBPTBal.post           = bPool.balanceOf(stakeLocker);
        fdtSupply.post          = pool_a.totalSupply();
        principalOut.post       = pool_a.principalOut();
        bptShortfall.post       = pool_a.bptShortfall();

        assertEq(principalOut.pre,       100_000_000 * USD);  // Total Pool Value (TPV) = PO + LLBal = 510m
        assertEq(liquidityLockerBal.pre, 410_000_000 * USD);

        assertEq(slBPTBal.pre,  10 * WAD);  // Assert pre-burn BPT balance
        assertLt(slBPTBal.post,     1E10);  // Dusty stakeLocker BPT return bal (less than 1e-8 WAD), meaning essentially all BPTs were burned

        assertEq(bptShortfall.pre,                 0);  // No bptShortfall before bpt burning occurs
        assertGt(bptShortfall.post, 40_000_000 * USD);  // Over $40m in shortfall after liquidation and BPT burn

        assertEq(fdtSupply.pre,  510_000_000 * WAD);  // TPV = fdtSupply + interestSum - shortfall = PO + LLBal
        assertEq(fdtSupply.post, 510_000_000 * WAD);  // TPV = 510m + 0 - 0

        assertEq(liquidityLockerBal.pre  + principalOut.pre,                      510_000_000 * USD);  // TPV = LLBal + PO + shortfall = 510m (shortfall = aggregate unrecognizedLosses of LPs)
        assertEq(liquidityLockerBal.post + principalOut.post + bptShortfall.post, 510_000_000 * USD);  // LLBal + PO goes down, bptShortfall distributes that loss - TPV = LL + PO + SF stays constant

        withinDiff(principalOut.post, 0, 1);  // Principal out is set to zero after claim has been made (with dust)

        /********************************************************/
        /*** Liquidity Provider Minimum Withdrawal Accounting ***/
        /********************************************************/

        bob_recognizeableLosses.pre = pool_a.recognizeableLossesOf(address(bob));  // Unrealized losses of bob from shortfall

        assertTrue(!bob.try_withdraw(address(pool_a), bob_recognizeableLosses.pre - 1));  // Cannot withdraw less than recognizeableLosses

        bob_usdcBal.pre = IERC20(USDC).balanceOf(address(bob));  // Bob USDC bal
        bob_poolBal.pre = pool_a.balanceOf(address(bob));        // Bob FDT  bal

        // Withdraw lowest possible amount (amt == recognizeableLosses)
        // NOTE: LPs can withdraw more than this amount, it will just go towards their USDC
        assertTrue(bob.try_withdraw(address(pool_a), bob_recognizeableLosses.pre));

        assertPoolAccounting(pool_a);

        bob_recognizeableLosses.post = pool_a.recognizeableLossesOf(address(bob));  // Unrealized losses of bob after withdrawal

        bob_usdcBal.post = IERC20(USDC).balanceOf(address(bob));  // Bob USDC bal
        bob_poolBal.post = pool_a.balanceOf(address(bob));        // Bob FDT  bal

        liquidityLockerBal.pre  = liquidityLockerBal.post;                  // Update pre/post variables for withdrawal checks
        liquidityLockerBal.post = IERC20(USDC).balanceOf(liquidityLocker);  // Update pre/post variables for withdrawal checks

        fdtSupply.pre  = fdtSupply.post;        // Update pre/post variables for withdrawal checks
        fdtSupply.post = pool_a.totalSupply();  // Update pre/post variables for withdrawal checks

        bptShortfall.pre  = bptShortfall.post;      // Update pre/post variables for withdrawal checks
        bptShortfall.post = pool_a.bptShortfall();  // Update pre/post variables for withdrawal checks

        assertEq(bob_recognizeableLosses.post, 0);  // After withdrawal, bob has zero unrecognized losses

        assertEq(bob_usdcBal.pre,  0);  // Deposited entire balance into pool
        assertEq(bob_usdcBal.post, 0);  // Withdrew enough just to realize losses, no USDC was transferred out of LL

        assertEq(bob_usdcBal.post - bob_usdcBal.pre,   0);                                        // Bob's USDC value withdrawn did not increase
        assertEq(bob_poolBal.pre  - bob_poolBal.post,  bob_recognizeableLosses.pre * WAD / 1E6);  // Bob's FDTs have been burned (doing assertion in WAD precision)
        assertEq(fdtSupply.pre    - fdtSupply.post,    bob_recognizeableLosses.pre * WAD / 1E6);  // Bob's FDTs have been burned (doing assertion in WAD precision)
        assertEq(bptShortfall.pre - bptShortfall.post, bob_recognizeableLosses.pre);              // BPT shortfall accounting has been decremented by Bob's recognized losses 

        assertEq(liquidityLockerBal.pre - liquidityLockerBal.post, 0);  // No USDC was transferred out of LL

        /**********************************************************/
        /*** Liquidity Provider Post-Loss Withdrawal Accounting ***/
        /**********************************************************/

        bob_usdcBal.pre = bob_usdcBal.post;  // Bob USDC bal
        bob_poolBal.pre = bob_poolBal.post;  // Bob FDT  bal

        uint256 withdrawAmt = bob_poolBal.pre * 1E6 / WAD;

        assertTrue(bob.try_withdraw(address(pool_a), withdrawAmt));  // Withdraw max amount

        assertPoolAccounting(pool_a);

        bob_usdcBal.post = IERC20(USDC).balanceOf(address(bob));  // Bob USDC bal
        bob_poolBal.post = pool_a.balanceOf(address(bob));        // Bob FDT  bal

        liquidityLockerBal.pre  = liquidityLockerBal.post;                  // Update pre/post variables for withdrawal checks
        liquidityLockerBal.post = IERC20(USDC).balanceOf(liquidityLocker);  // Update pre/post variables for withdrawal checks

        fdtSupply.pre  = fdtSupply.post;        // Update pre/post variables for withdrawal checks
        fdtSupply.post = pool_a.totalSupply();  // Update pre/post variables for withdrawal checks

        assertEq(bob_usdcBal.pre,  0);            // Deposited entire balance into pool
        assertEq(bob_usdcBal.post, withdrawAmt);  // Withdrew enough just to realize losses, no USDC was transferred out of LL

        assertEq(bob_poolBal.post, 0);  // Withdrew entire amount, so all remaining BPTs are burned

        assertEq(fdtSupply.pre - fdtSupply.post, bob_poolBal.pre); // Bob's FDTs have been burned

        assertEq(liquidityLockerBal.pre - liquidityLockerBal.post, withdrawAmt);  // All Bob's USDC was transferred out of LL
    }
} 
