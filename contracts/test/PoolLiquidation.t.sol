
// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "./user/Borrower.sol";
import "./user/Governor.sol";
import "./user/Lender.sol";
import "./user/LP.sol";
import "./user/PoolDelegate.sol";
import "./user/Staker.sol";
import "./user/EmergencyAdmin.sol";

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
import "../Pool.sol";
import "../PoolFactory.sol";
import "../PremiumCalc.sol";
import "../StakeLockerFactory.sol";

import "../oracles/ChainlinkOracle.sol";
import "../oracles/UsdOracle.sol";

import "module/maple-token/contracts/MapleToken.sol";

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
    Lender                                 fay;
    PoolDelegate                           sid;
    PoolDelegate                           joe;
    EmergencyAdmin                         mic;

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

    function setUp() public {

        che            = new Borrower();                     // Actor: Borrower of the Loan.
        gov            = new Governor();                     // Actor: Governor of Maple.
        sid            = new PoolDelegate();                 // Actor: Manager of the pool_a.
        joe            = new PoolDelegate();                 // Actor: Manager of the pool_b.
        ali            = new LP();                           // Actor: Liquidity provider.
        bob            = new LP();                           // Actor: Liquidity provider.
        dan            = new Staker();                       // Actor: Stakes BPTs in Pool.
        eli            = new Staker();                       // Actor: Stakes BPTs in Pool.
        fay            = new Lender();                       // Actor: Funds loan directly (test liquidation)
        mic            = new EmergencyAdmin();               // Actor: Emergency Admin of the protocol.

        mpl            = new MapleToken("MapleToken", "MAPL", USDC);
        globals        = gov.createGlobals(address(mpl));
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

        gov.setDefaultUniswapPath(WETH, USDC, USDC);
        gov.setDefaultUniswapPath(WBTC, USDC, WETH);

        gov.setMaxSwapSlippage(2000);  // Set to 20% for the sake of the BPT shortfall test

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
        gov.setAdmin(address(mic));
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
        gov.setLiquidityAsset(USDC,         true);
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
        sid.setOpenToPublic(address(pool_a), true);
        joe.setOpenToPublic(address(pool_b), true);
        
        assertEq(uint256(pool_a.poolState()), 1);  // Finalize
        assertEq(uint256(pool_b.poolState()), 1);  // Finalize
    }

    function test_triggerDefault_pool_delegate() public {
        // Fund the pool
        mint("USDC", address(ali), 100_000_000 * USD);
        ali.approve(USDC, address(pool_a), MAX_UINT);
        ali.approve(USDC, address(pool_b), MAX_UINT);
        ali.deposit(address(pool_a), 80_000_000 * USD + 1);
        ali.deposit(address(pool_b), 20_000_000 * USD - 1);

        // Fund the loan
        sid.fundLoan(address(pool_a), address(loan), address(dlFactory), 80_000_000 * USD + 1);  // Plus 1e-6 to create exact 100m totalSupply
        joe.fundLoan(address(pool_b), address(loan), address(dlFactory), 20_000_000 * USD - 1);  // 20% minus 1e-6 equity 

        // Drawdown loan
        uint cReq = loan.collateralRequiredForDrawdown(4_000_000 * USD);
        mint("WETH", address(che), cReq);
        che.approve(WETH, address(loan), MAX_UINT);
        che.drawdown(address(loan), 4_000_000 * USD);  // Draw down less than total amount
        
        // Warp to late payment
        uint256 start = block.timestamp;
        uint256 nextPaymentDue = loan.nextPaymentDue();
        uint256 gracePeriod = globals.gracePeriod();
        hevm.warp(start + nextPaymentDue + gracePeriod + 1);

        // Attempt to trigger default as PD holding less than minimum LoanFDTs required (MapleGlobals.minLoanEquity)
        assertTrue(!joe.try_triggerDefault(address(pool_b), address(loan), address(dlFactory)));

        // Update storage to have exactly 20% equity (totalSupply remains the same)
        hevm.store(
            address(loan),
            keccak256(abi.encode(address(pool_b.debtLockers(address(loan), address(dlFactory))), 0)), // Overwrite balance to have exact 20% equity
            bytes32(uint256(20_000_000 * WAD))
        );

        // Pause protocol and attempt triggerDefault()
        assertTrue( mic.try_setProtocolPause(address(globals), true));
        assertTrue(!joe.try_triggerDefault(address(pool_b), address(loan), address(dlFactory)));

        // Unpause protocol and triggerDefault()
        assertTrue(mic.try_setProtocolPause(address(globals), false));
        assertTrue(joe.try_triggerDefault(address(pool_b), address(loan), address(dlFactory)));
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
        sid.triggerDefault(address(pool_a), address(loan), address(dlFactory));
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

        // Call claim again to make sure that default isn't double accounted
        vals_a = sid.claim(address(pool_a), address(loan),  address(dlFactory));
        vals_b = joe.claim(address(pool_b), address(loan),  address(dlFactory));
        assertEq(vals_a[6], 0);
        assertEq(vals_b[6], 0);
    }

    function test_claim_default_burn_BPT_full_recover() public {

        setUpLoanAndDefault();

        TestObj memory liquidityLocker_a_bal;
        TestObj memory liquidityLocker_b_bal;
        TestObj memory stakeLocker_a_bal;
        TestObj memory stakeLocker_b_bal;
        TestObj memory principalOut_a;
        TestObj memory principalOut_b;

        address liquidityLocker_a = pool_a.liquidityLocker();
        address liquidityLocker_b = pool_b.liquidityLocker();

        // Pre-state liquidityLocker checks.
        liquidityLocker_a_bal.pre = IERC20(USDC).balanceOf(liquidityLocker_a);
        liquidityLocker_b_bal.pre = IERC20(USDC).balanceOf(liquidityLocker_b);

        stakeLocker_a_bal.pre = bPool.balanceOf(address(stakeLocker_a));
        stakeLocker_b_bal.pre = bPool.balanceOf(address(stakeLocker_b));

        principalOut_a.pre = pool_a.principalOut();
        principalOut_b.pre = pool_b.principalOut();

        assertEq(principalOut_a.pre, 1_000_000 * USD);
        assertEq(principalOut_b.pre, 3_000_000 * USD);

        assertEq(stakeLocker_a_bal.pre, 10 * WAD);
        assertEq(stakeLocker_b_bal.pre, 25 * WAD);

        assertEq(liquidityLocker_a_bal.pre, 9_000_000 * USD);
        assertEq(liquidityLocker_b_bal.pre, 7_000_000 * USD);

        sid.claim(address(pool_a), address(loan),  address(dlFactory));
        joe.claim(address(pool_b), address(loan),  address(dlFactory));

        // Post-state liquidityLocker checks.
        liquidityLocker_a_bal.post = IERC20(USDC).balanceOf(liquidityLocker_a);
        liquidityLocker_b_bal.post = IERC20(USDC).balanceOf(liquidityLocker_b);

        stakeLocker_a_bal.post = bPool.balanceOf(address(stakeLocker_a));
        stakeLocker_b_bal.post = bPool.balanceOf(address(stakeLocker_b));

        principalOut_a.post = pool_a.principalOut();
        principalOut_b.post = pool_b.principalOut();
        
        withinDiff(liquidityLocker_a_bal.post - liquidityLocker_a_bal.pre, 1_000_000 * USD, 1);  // Entire initial loan amount was recovered between liquidation and burn
        withinDiff(liquidityLocker_b_bal.post - liquidityLocker_b_bal.pre, 3_000_000 * USD, 1);  // Entire initial loan amount was recovered between liquidation and burn

        withinDiff(principalOut_a.post, 0, 1);  // Principal out is set to zero (with dust)
        withinDiff(principalOut_b.post, 0, 1);  // Principal out is set to zero (with dust)

        assertEq(liquidityLocker_a_bal.pre  + principalOut_a.pre,  10_000_000 * USD);  // Total pool value = 9m + 1m = 10m
        assertEq(liquidityLocker_a_bal.post + principalOut_a.post, 10_000_000 * USD);  // Total pool value = 10m + 0 = 10m (successful full coverage from liquidation + staker burn)

        assertEq(liquidityLocker_b_bal.pre  + principalOut_b.pre,  10_000_000 * USD);  // Total pool value = 7m + 3m = 10m
        assertEq(liquidityLocker_b_bal.post + principalOut_b.post, 10_000_000 * USD);  // Total pool value = 1m + 0 = 10m (successful full coverage from liquidation + staker burn)

        assertTrue(stakeLocker_a_bal.pre - stakeLocker_a_bal.post > 0);  // Assert BPTs were burned
        assertTrue(stakeLocker_b_bal.pre - stakeLocker_b_bal.post > 0);  // Assert BPTs were burned

        assertEq(stakeLocker_a_bal.pre - stakeLocker_a_bal.post, stakeLocker_a.bptLosses());  // Assert FDT loss accounting
        assertEq(stakeLocker_a_bal.pre - stakeLocker_a_bal.post, stakeLocker_a.bptLosses());  // Assert FDT loss accounting
    }

    function assertPoolAccounting(Pool pool) internal {
        uint256 liquidityAssetDecimals = IERC20Details(address(pool.liquidityAsset())).decimals();

        uint256 liquidityLockerBal = pool.liquidityAsset().balanceOf(pool.liquidityLocker());
        uint256 fdtTotalSupply     = pool.totalSupply().mul(10 ** liquidityAssetDecimals).div(WAD);  // Convert to liquidityAsset precision
        uint256 principalOut       = pool.principalOut();
        uint256 interestSum        = pool.interestSum();
        uint256 poolLosses         = pool.poolLosses();

        // Total Pool Value = LLBal + PO = fdtSupply + interestSum + aggregate unrecognized losses
        assertEq(liquidityLockerBal + principalOut, fdtTotalSupply + interestSum - poolLosses, "Pool accounting compromised");
    }

    function test_claim_default_burn_BPT_shortfall() public {

        // Fund the pool
        mint("USDC", address(ali), 500_000_000 * USD);
        mint("USDC", address(bob),  10_000_000 * USD);

        ali.approve(USDC, address(pool_a), MAX_UINT);
        bob.approve(USDC, address(pool_a), MAX_UINT);
        ali.deposit(address(pool_a), 500_000_000 * USD);  // Ali symbolizes all other LPs, test focuses on Bob
        bob.deposit(address(pool_a), 10_000_000 * USD);
        assertTrue(bob.try_intendToWithdraw(address(pool_a)));

        assertPoolAccounting(pool_a);

        // Fund the loan
        sid.fundLoan(address(pool_a), address(loan), address(dlFactory), 100_000_000 * USD);
        uint cReq = loan.collateralRequiredForDrawdown(100_000_000 * USD);

        assertPoolAccounting(pool_a);

        // Drawdown loan
        mint("WETH", address(che), cReq);
        che.approve(WETH, address(loan), MAX_UINT);
        che.drawdown(address(loan), 100_000_000 * USD);

        assertPoolAccounting(pool_a);

        // Warp to late payment
        hevm.warp(block.timestamp + loan.nextPaymentDue() + globals.gracePeriod() + 1);

        // Trigger default
        sid.triggerDefault(address(pool_a), address(loan), address(dlFactory));

        // Instantiate all test variables
        TestObj memory liquidityLockerBal;
        TestObj memory slBPTBal;
        TestObj memory fdtSupply;
        TestObj memory principalOut;
        TestObj memory poolLosses;
        TestObj memory bob_usdcBal;
        TestObj memory bob_poolBal;
        TestObj memory bob_recognizableLosses;

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
        poolLosses.pre         = pool_a.poolLosses();

        uint256[7] memory vals_a = sid.claim(address(pool_a), address(loan),  address(dlFactory));

        assertPoolAccounting(pool_a);

        // Pre-claim accounting checks
        liquidityLockerBal.post = IERC20(USDC).balanceOf(liquidityLocker);
        slBPTBal.post           = bPool.balanceOf(stakeLocker);
        fdtSupply.post          = pool_a.totalSupply();
        principalOut.post       = pool_a.principalOut();
        poolLosses.post         = pool_a.poolLosses();

        assertEq(principalOut.pre,       100_000_000 * USD);  // Total Pool Value (TPV) = PO + LLBal = 510m
        assertEq(liquidityLockerBal.pre, 410_000_000 * USD);

        assertEq(slBPTBal.pre,  10 * WAD);  // Assert pre-burn BPT balance
        assertLt(slBPTBal.post,     1E10);  // Dusty stakeLocker BPT return bal (less than 1e-8 WAD), meaning essentially all BPTs were burned

        assertEq(slBPTBal.pre - slBPTBal.post, IStakeLocker(stakeLocker).bptLosses());  // Assert FDT loss accounting

        assertEq(poolLosses.pre,                 0);  // No poolLosses before bpt burning occurs
        assertGt(poolLosses.post, 40_000_000 * USD);  // Over $40m in shortfall after liquidation and BPT burn

        assertEq(fdtSupply.pre,  510_000_000 * WAD);  // TPV = fdtSupply + interestSum - shortfall = PO + LLBal
        assertEq(fdtSupply.post, 510_000_000 * WAD);  // TPV = 510m + 0 - 0

        assertEq(liquidityLockerBal.pre  + principalOut.pre,                    510_000_000 * USD);  // TPV = LLBal + PO + shortfall = 510m (shortfall = aggregate unrecognizedLosses of LPs)
        assertEq(liquidityLockerBal.post + principalOut.post + poolLosses.post, 510_000_000 * USD);  // LLBal + PO goes down, poolLosses distributes that loss - TPV = LL + PO + SF stays constant

        withinDiff(principalOut.post, 0, 1);  // Principal out is set to zero after claim has been made (with dust)

        /********************************************************/
        /*** Liquidity Provider Minimum Withdrawal Accounting ***/
        /********************************************************/

        make_withdrawable(bob, pool_a);

        bob_recognizableLosses.pre = pool_a.recognizableLossesOf(address(bob));  // Unrealized losses of bob from shortfall

        assertTrue(!bob.try_withdraw(address(pool_a), bob_recognizableLosses.pre - 1));  // Cannot withdraw less than recognizableLosses

        bob_usdcBal.pre = IERC20(USDC).balanceOf(address(bob));  // Bob USDC bal
        bob_poolBal.pre = pool_a.balanceOf(address(bob));        // Bob FDT  bal

        // Withdraw lowest possible amount (amt == recognizableLosses)
        // NOTE: LPs can withdraw more than this amount, it will just go towards their USDC
        assertTrue(!bob.try_transfer(address(pool_a), address(ali), bob_poolBal.pre));
        assertTrue( bob.try_withdraw(address(pool_a), bob_recognizableLosses.pre));

        assertPoolAccounting(pool_a);

        bob_recognizableLosses.post = pool_a.recognizableLossesOf(address(bob));  // Unrealized losses of bob after withdrawal

        bob_usdcBal.post = IERC20(USDC).balanceOf(address(bob));  // Bob USDC bal
        bob_poolBal.post = pool_a.balanceOf(address(bob));        // Bob FDT  bal

        liquidityLockerBal.pre  = liquidityLockerBal.post;                  // Update pre/post variables for withdrawal checks
        liquidityLockerBal.post = IERC20(USDC).balanceOf(liquidityLocker);  // Update pre/post variables for withdrawal checks

        fdtSupply.pre  = fdtSupply.post;        // Update pre/post variables for withdrawal checks
        fdtSupply.post = pool_a.totalSupply();  // Update pre/post variables for withdrawal checks

        poolLosses.pre  = poolLosses.post;      // Update pre/post variables for withdrawal checks
        poolLosses.post = pool_a.poolLosses();  // Update pre/post variables for withdrawal checks

        assertEq(bob_recognizableLosses.post, 0);  // After withdrawal, bob has zero unrecognized losses

        assertEq(bob_usdcBal.pre,  0);  // Deposited entire balance into pool
        assertEq(bob_usdcBal.post, 0);  // Withdrew enough just to realize losses, no USDC was transferred out of LL

        assertEq(bob_usdcBal.post - bob_usdcBal.pre,  0);                                       // Bob's USDC value withdrawn did not increase
        assertEq(bob_poolBal.pre  - bob_poolBal.post, bob_recognizableLosses.pre * WAD / 1E6);  // Bob's FDTs have been burned (doing assertion in WAD precision)
        assertEq(fdtSupply.pre    - fdtSupply.post,   bob_recognizableLosses.pre * WAD / 1E6);  // Bob's FDTs have been burned (doing assertion in WAD precision)
        assertEq(poolLosses.pre   - poolLosses.post,  bob_recognizableLosses.pre);              // BPT shortfall accounting has been decremented by Bob's recognized losses 

        assertEq(liquidityLockerBal.pre - liquidityLockerBal.post, 0);  // No USDC was transferred out of LL

        /**********************************************************/
        /*** Liquidity Provider Post-Loss Withdrawal Accounting ***/
        /**********************************************************/

        bob_usdcBal.pre = bob_usdcBal.post;  // Bob USDC bal
        bob_poolBal.pre = bob_poolBal.post;  // Bob FDT  bal

        uint256 withdrawAmt = bob_poolBal.pre * 1E6 / WAD;

        make_withdrawable(bob, pool_a);

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

    function make_withdrawable(LP investor, Pool pool) public {
        uint256 currentTime = block.timestamp;
        assertTrue(investor.try_intendToWithdraw(address(pool)));
        assertEq(      pool.depositCooldown(address(investor)), currentTime, "Incorrect value set");
        hevm.warp(currentTime + globals.cooldownPeriod() + 1);
    }
} 
