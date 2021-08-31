// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { TestUtils } from "../../modules/contract-test-utils/contracts/test.sol";

import { IBFactory } from "./interfaces/Interfaces.sol";

import { GlobalAdmin }       from "./accounts/GlobalAdmin.sol";
import { Governor }          from "./accounts/Governor.sol";
import { Borrower }          from "./accounts/Borrower.sol";
import { PoolDelegate }      from "./accounts/PoolDelegate.sol";
import { LiquidityProvider } from "./accounts/LiquidityProvider.sol";
import { Explorer }          from "./accounts/Explorer.sol";

import { MapleGlobals, IMapleGlobals }                           from "../../modules/globals/contracts/MapleGlobals.sol";
import { LoanFactory, ILoanFactory }                             from "../../modules/loan/contracts/LoanFactory.sol";
import { ILoan }                                                 from "../../modules/loan/contracts/interfaces/ILoan.sol";
import { PoolFactory, IPoolFactory }                             from "../../modules/pool/contracts/PoolFactory.sol";
import { IPool }                                                 from "../../modules/pool/contracts/interfaces/IPool.sol";
import { FundingLockerFactory, IFundingLockerFactory }           from "../../modules/funding-locker/contracts/FundingLockerFactory.sol";
import { CollateralLockerFactory, ICollateralLockerFactory }     from "../../modules/collateral-locker/contracts/CollateralLockerFactory.sol";
import { StakeLockerFactory, IStakeLockerFactory }               from "../../modules/stake-locker/contracts/StakeLockerFactory.sol";
import { IStakeLocker }                                          from "../../modules/stake-locker/contracts/interfaces/IStakeLocker.sol";
import { LiquidityLockerFactory, ILiquidityLockerFactory }       from "../../modules/liquidity-locker/contracts/LiquidityLockerFactory.sol";
import { IERC20 }                                                from "../../modules/loan/modules/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IBPoolLike }                                            from "../../modules/pool/contracts/interfaces/interfaces.sol";
import { LateFeeCalc, ILateFeeCalc }                             from "../../modules/late-fee-calculator/contracts/LateFeeCalc.sol";
import { RepaymentCalc, IRepaymentCalc }                         from "../../modules/repayment-calculator/contracts/RepaymentCalc.sol";
import { PremiumCalc, IPremiumCalc }                             from "../../modules/premium-calculator/contracts/PremiumCalc.sol";
import { DebtLockerFactory, IDebtLockerFactory }                 from "../../modules/debt-locker/contracts/DebtLockerFactory.sol";
import { ChainlinkOracle, IChainlinkOracle }                     from "../../modules/chainlink-oracle/contracts/ChainlinkOracle.sol";
import { UsdOracle, IUsdOracle }                                 from "../../modules/usd-oracle/contracts/UsdOracle.sol";
import { Pausable }                                              from "../../modules/loan/modules/openzeppelin-contracts/contracts/utils/Pausable.sol";
import { IMapleTreasury, MapleTreasury }                         from "../../modules/treasury/contracts/MapleTreasury.sol";
import { IBasicFDT }                                             from "../../modules/loan/modules/funds-distribution-token/contracts/interfaces/IBasicFDT.sol";

contract LoanTestUtil is TestUtils {

    address constant DAI  = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant MPL  = 0x33349B282065b0284d756F0577FB39c158F935e6;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address constant BPOOL_FACTORY        = 0x9424B1412450D0f8Fc2255FAf6046b98213B76Bd; // Balancer pool factory
    address constant WETH_AGGREGATOR      = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant UNISWAP_V2_ROUTER_02 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    uint256 constant USDC_SLOT = 9;
    uint256 constant MPL_SLOT  = 0;
    uint256 constant WETH_SLOT = 3;
    uint256 constant DAI_SLOT  = 2;

    IERC20 constant usdc = IERC20(USDC);
    IERC20 constant mpl  = IERC20(MPL);
    IERC20 constant weth = IERC20(WETH);
    IERC20 constant dai  = IERC20(DAI);

    // Setup for loan creation - 

    // 1. Deploy funding locker factory
    // 2. Deploy collateral locker factory.
    // 3. Deploy the globalAdmin. 
    // 4. Deploy the globals.  -- Use already deployed MPL address.
    // 5. Deploy the loan factory.
    // 6. whitelist the L, FL & CL factory with globals.


    function deployGlobals(address mplToken, address gov) public returns (IMapleGlobals globals, GlobalAdmin globalAdmin) {
        globals = new MapleGlobals(gov, mplToken, address(globalAdmin = new GlobalAdmin()));
    }

    function deployFactories(address globals) public returns(ILoanFactory loanFactory, IPoolFactory poolFactory) {
        return (new LoanFactory(globals), new PoolFactory(globals));
    }

    function deployLoanSubFactories() public returns(ICollateralLockerFactory clFactory, IFundingLockerFactory flFactory) {
        return (new CollateralLockerFactory(), new FundingLockerFactory());
    }

    function deployPoolSubFactories() public returns(IStakeLockerFactory slFactory, ILiquidityLockerFactory llFactory, IDebtLockerFactory dlFactory) {
        return (new StakeLockerFactory(), new LiquidityLockerFactory(), new DebtLockerFactory());
    }

    function validateFactories(address globals, Governor gov, address loanFactory, address poolFactory, address clFactory, address flFactory, address slFactory, address llFactory, address dlFactory) public {
        gov.mapleGlobals_setValidLoanFactory(globals, loanFactory, true);
        gov.mapleGlobals_setValidPoolFactory(globals, poolFactory, true);
        gov.mapleGlobals_setValidSubFactory( globals, loanFactory, clFactory, true);
        gov.mapleGlobals_setValidSubFactory( globals, loanFactory, flFactory, true);
        gov.mapleGlobals_setValidSubFactory( globals, poolFactory, slFactory, true);
        gov.mapleGlobals_setValidSubFactory( globals, poolFactory, llFactory, true);
        gov.mapleGlobals_setValidSubFactory( globals, poolFactory, dlFactory, true);
    }

    function deployBalancerPool(address globals, uint256 usdcAmount, uint256 mplAmount, Governor gov) public returns (IBPoolLike bPool) {
        // Mint USDC into this account
        mint(USDC, USDC_SLOT, address(this), usdcAmount);
        mint(MPL, MPL_SLOT, address(this), mplAmount);

        // Initialize MPL/USDC Balancer Pool and whitelist
        bPool = IBPoolLike(IBFactory(BPOOL_FACTORY).newBPool());
        usdc.approve(address(bPool), MAX_UINT);
        mpl.approve(address(bPool),  MAX_UINT);
        bPool.bind(USDC,         usdcAmount, 5 ether);  // Bind USDC with 5 denormalization weight
        bPool.bind(address(mpl),  mplAmount, 5 ether);  // Bind  MPL with 5 denormalization weight
        bPool.finalize();
        gov.mapleGlobals_setValidBalancerPool(globals, address(bPool), true);
    }

    function transferBptsToPoolDelegate(IBPoolLike bPool, address poolDelegate) public {
        bPool.transfer(poolDelegate, 50 * WAD);  // Give PD a balance of BPTs to finalize pool
    }

    function stakeAndFinalizePool(uint256 stakeAmt, IPool pool, PoolDelegate pd, address bPool) public {
        IStakeLocker stakeLocker = IStakeLocker(pool.stakeLocker());
        pd.approve(bPool, address(stakeLocker), MAX_UINT);
        pd.stakelocker_stake(address(stakeLocker), stakeAmt);
        pd.pool_finalize(address(pool));
        pd.pool_setOpenToPublic(address(pool), true);
    }

    function deployPool(PoolDelegate pd, IPoolFactory poolFactory, address liquidityAsset, address stakeAsset, address slFactory, address llFactory) public returns (IPool pool) {
        pd.createPool(address(poolFactory), USDC, address(stakeAsset), address(slFactory), address(llFactory), 500, 500, MAX_UINT);
        pool = IPool(poolFactory.pools(poolFactory.poolsCreated() - 1));
    }

    function deployCalcsAndValidate(address globals, Governor gov) public returns (ILateFeeCalc lateFeeCalc, IPremiumCalc premiumCalc, IRepaymentCalc repaymentCalc) {
        lateFeeCalc   = new LateFeeCalc(5);
        premiumCalc   = new PremiumCalc(500);
        repaymentCalc = new RepaymentCalc();
        gov.mapleGlobals_setCalc(globals, address(lateFeeCalc),   true);
        gov.mapleGlobals_setCalc(globals, address(premiumCalc),   true);
        gov.mapleGlobals_setCalc(globals, address(repaymentCalc), true);
    }

    function deployOracles(address globals, Governor gov, address securityAdmin) public returns(IChainlinkOracle wethOracle, IUsdOracle usdOracle) {
        wethOracle = new ChainlinkOracle(WETH_AGGREGATOR, WETH, securityAdmin);
        usdOracle  = new UsdOracle();

        gov.mapleGlobals_setPriceOracle(globals, WETH, address(wethOracle));
        gov.mapleGlobals_setPriceOracle(globals, USDC, address(usdOracle));
    }

    function deployTreasury(address globals, Governor gov) public returns(IMapleTreasury mapleTreasury) {
        mapleTreasury = new MapleTreasury(MPL, USDC, UNISWAP_V2_ROUTER_02, globals); 
        gov.mapleGlobals_setMapleTreasury(globals, address(mapleTreasury));
    }

    function getFuzzedSpecs(
        uint256 apr,
        uint256 index,             // Random index for random payment interval
        uint256 numPayments,       // Used for termDays
        uint256 requestAmount,
        uint256 collateralRatio
    ) public pure returns (uint256[5] memory specs) {
        return getFuzzedSpecs(apr, index, numPayments, requestAmount, collateralRatio, 10_000 * USD, 10_000, 1E10 * USD);
    }

    function getFuzzedSpecs(
        uint256 apr,
        uint256 index,             // Random index for random payment interval
        uint256 numPayments,       // Used for termDays
        uint256 requestAmount,
        uint256 collateralRatio,
        uint256 minimumRequestAmt,
        uint256 maxCollateralRatio,
        uint256 maxRequestAmt
    ) public pure returns (uint256[5] memory specs) {
        uint16[10] memory paymentIntervalArray = [1, 2, 5, 7, 10, 15, 30, 60, 90, 360];
        numPayments = constrictToRange(numPayments, 5, 100, true);
        uint256 paymentIntervalDays = paymentIntervalArray[index % 10];  // TODO: Consider changing this approach
        uint256 termDays            = paymentIntervalDays * numPayments;

        specs = [
            constrictToRange(apr, 1, 10_000, true),                                   // APR between 0.01% and 100% (non-zero for test behavior)
            termDays,                                                                 // Fuzzed term days
            paymentIntervalDays,                                                      // Payment interval days from array
            constrictToRange(requestAmount, minimumRequestAmt, maxRequestAmt, true),  // 10k USD - 10b USD loans (non-zero) in general scenario
            constrictToRange(collateralRatio, 0, maxCollateralRatio)                  // Collateral ratio between 0 and maxCollateralRatio
        ];
    }

}

contract LoanTest is LoanTestUtil {

    Governor gov;
    ILoan loan;
    IMapleGlobals globals;
    ILoanFactory loanFactory;
    IPoolFactory poolFactory;
    ICollateralLockerFactory clFactory;
    IFundingLockerFactory flFactory;
    IStakeLockerFactory slFactory;
    ILiquidityLockerFactory llFactory;
    IDebtLockerFactory dlFactory;
    IBPoolLike bPool;
    ILateFeeCalc lateFeeCalc;
    IRepaymentCalc repaymentCalc;
    IPremiumCalc premiumCalc;
    IChainlinkOracle wethOracle;
    IUsdOracle usdOracle;
    IMapleTreasury treasury;

    IPool p1;
    IPool p2;
    PoolDelegate pd1;
    PoolDelegate pd2;
    GlobalAdmin  globalAdmin;
    Explorer ex;

    LP lp1;
    LP lp2;

    Borrower b1;
    Borrower b2;

    function setUp() public {
        gov  = new Governor();
        pd1  = new PoolDelegate();
        pd2  = new PoolDelegate();
        b1   = new Borrower();
        b2   = new Borrower();
        lp1  = new LP();
        lp2  = new LP();
        ex   = new Explorer();

        (globals, globalAdmin)                    = deployGlobals(MPL, address(gov));
        treasury                                  = deployTreasury(address(globals), gov);
        (wethOracle, usdOracle)                   = deployOracles(address(globals), gov, address(this));
        (loanFactory, poolFactory)                = deployFactories(address(globals));
        (clFactory, flFactory)                    = deployLoanSubFactories();
        (slFactory, llFactory, dlFactory)         = deployPoolSubFactories();
        bPool                                     = deployBalancerPool(address(globals), 1_550_000 * USD, 155_000 * WAD, gov);
        (lateFeeCalc, premiumCalc, repaymentCalc) = deployCalcsAndValidate(address(globals), gov);
        
        gov.mapleGlobals_setPoolDelegateAllowlist(address(globals), address(pd1), true);
        gov.mapleGlobals_setPoolDelegateAllowlist(address(globals), address(pd2), true);
        gov.mapleGlobals_setLiquidityAsset( address(globals), USDC, true);
        gov.mapleGlobals_setCollateralAsset(address(globals), USDC, true);
        gov.mapleGlobals_setCollateralAsset(address(globals), WETH, true);

        validateFactories(address(globals), gov, address(loanFactory), address(poolFactory), address(clFactory), address(flFactory), address(slFactory), address(llFactory), address(dlFactory));

        // Pool 1 setup
        p1 = deployPool(pd1, poolFactory, USDC, address(bPool), address(slFactory), address(llFactory));
        transferBptsToPoolDelegate(bPool, address(pd1));
        stakeAndFinalizePool(bPool.balanceOf(address(pd1)), p1, pd1, address(bPool));

        // Pool 2 setup
        p2 = deployPool(pd2, poolFactory, USDC, address(bPool), address(slFactory), address(llFactory));
        transferBptsToPoolDelegate(bPool, address(pd2));
        stakeAndFinalizePool(bPool.balanceOf(address(pd2)), p2, pd2, address(bPool));
    }

    function test_fundLoan(
        uint256 apr,
        uint256 index,
        uint256 numPayments,
        uint256 requestAmount,
        uint256 collateralRatio,
        uint256 fundAmount,
        uint256 fundAmount2
    )
        public
    {
        uint256[5] memory specs = getFuzzedSpecs(apr, index, numPayments, requestAmount, collateralRatio);
        address[3] memory calcs = [address(repaymentCalc), address(lateFeeCalc), address(premiumCalc)];

        loan = ILoan(b1.loanFactory_createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));

        address fundingLocker   = loan.fundingLocker();
        address liquidityLocker = p1.liquidityLocker();

        fundAmount = constrictToRange(fundAmount, 1 * USD, 1E10 * USD);
        uint256 wadAmount = fundAmount * WAD / USD;

        fundAmount2 = constrictToRange(fundAmount, 1 * USD, 1E10 * USD);
        uint256 wadAmount2 = fundAmount2 * WAD / USD;

        mint(USDC, USDC_SLOT, address(lp1), (fundAmount + fundAmount2));
        lp1.approve(USDC, address(p1),    (fundAmount + fundAmount2));
        lp1.pool_deposit(address(p1),          (fundAmount + fundAmount2));

        // Note: Cannot do pre-state check for LoanFDT balance of debtLocker since it is not instantiated
        assertEq(usdc.balanceOf(address(fundingLocker)),                            0);
        assertEq(usdc.balanceOf(address(liquidityLocker)), (fundAmount + fundAmount2));

        // Loan-specific pause by Borrower
        assertTrue(!Pausable(address(loan)).paused());
        assertTrue(b1.try_loan_pause(address(loan)));
        assertTrue(Pausable(address(loan)).paused());
        assertTrue(!pd1.try_pool_fundLoan(address(p1), address(loan), address(dlFactory), fundAmount));  // Allow for two fundings

        assertTrue(b1.try_loan_unpause(address(loan)));
        assertTrue(!Pausable(address(loan)).paused());

        uint256 start = block.timestamp;

        hevm.warp(start + globals.fundingPeriod() + 1);  // Warp to past fundingPeriod, loan cannot be funded
        assertTrue(!pd1.try_pool_fundLoan(address(p1), address(loan), address(dlFactory), fundAmount));

        hevm.warp(start + globals.fundingPeriod());  // Warp to fundingPeriod, loan can be funded
        assertTrue(pd1.try_pool_fundLoan(address(p1), address(loan), address(dlFactory), fundAmount));

        address debtLocker = p1.debtLockers(address(loan), address(dlFactory));

        assertEq(IERC20(address(loan)).balanceOf(address(debtLocker)), wadAmount);
        assertEq(usdc.balanceOf(address(fundingLocker)),              fundAmount);
        assertEq(usdc.balanceOf(address(liquidityLocker)),           fundAmount2);

        // Protocol-wide pause by Emergency Admin
        assertTrue(globalAdmin.try_mapleGlobals_setProtocolPause(address(globals), true));
        assertTrue(globals.protocolPaused());
        assertTrue(!pd1.try_pool_fundLoan(address(p1), address(loan), address(dlFactory), fundAmount2));

        assertTrue(globalAdmin.try_mapleGlobals_setProtocolPause(address(globals), false));
        assertTrue(!globals.protocolPaused());
        assertTrue(pd1.try_pool_fundLoan(address(p1), address(loan), address(dlFactory), fundAmount2));

        assertEq(IERC20(address(loan)).balanceOf(address(debtLocker)),  wadAmount + wadAmount2);
        assertEq(usdc.balanceOf(address(fundingLocker)),                fundAmount + fundAmount2);
        assertEq(usdc.balanceOf(address(liquidityLocker)),              0);
    }

    function instantiateAndFundLoan(
        uint256 apr,
        uint256 index,
        uint256 numPayments,
        uint256 requestAmount,
        uint256 collateralRatio,
        uint256 fundAmount
    )
        internal returns (ILoan _loan)
    {
        uint256[5] memory specs = getFuzzedSpecs(apr, index, numPayments, requestAmount, collateralRatio);
        address[3] memory calcs = [address(repaymentCalc), address(lateFeeCalc), address(premiumCalc)];

        _loan = ILoan(b1.loanFactory_createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));

        fundAmount = constrictToRange(fundAmount, specs[3], 1E10 * USD, true);  // Fund between requestAmount and 10b USD
        uint256 wadAmount = fundAmount * WAD / USD;

        mint(USDC, USDC_SLOT, address(lp1), fundAmount);
        lp1.approve(USDC, address(p1),      fundAmount);
        lp1.pool_deposit(address(p1),       fundAmount);

        pd1.pool_fundLoan(address(p1), address(_loan), address(dlFactory), fundAmount);
    }

    function assertLoanState(
        ILoan loan_,
        uint256 loanState,
        uint256 principalOwed,
        uint256 principalPaid,
        uint256 interestPaid,
        uint256 loanBalance,
        uint256 paymentsRemaining,
        uint256 nextPaymentDue
    )
        internal
    {
        assertEq(uint256(loan_.loanState()),             loanState);
        assertEq(loan_.principalOwed(),              principalOwed);
        assertEq(loan_.principalPaid(),              principalPaid);
        assertEq(loan_.interestPaid(),                interestPaid);
        assertEq(usdc.balanceOf(address(loan_)),       loanBalance);
        assertEq(loan_.paymentsRemaining(),      paymentsRemaining);
        assertEq(loan_.nextPaymentDue(),            nextPaymentDue);
    }

    function drawdown(ILoan loan_, uint256 drawdownAmount) internal returns (uint256 reqCollateral) {
        reqCollateral = loan_.collateralRequiredForDrawdown(drawdownAmount);
        mint(WETH, WETH_SLOT, address(b1), reqCollateral);
        b1.erc20_approve(WETH, address(loan_), reqCollateral);
        assertTrue(b1.try_loan_drawdown(address(loan_), drawdownAmount));  // Borrow draws down on loan
    }

    function test_collateralRequiredForDrawdown(
        uint256 apr,
        uint256 index,
        uint256 numPayments,
        uint256 requestAmount,
        uint256 collateralRatio,
        uint256 fundAmount,
        uint256 drawdownAmount
    )
        public
    {
        loan = instantiateAndFundLoan(apr, index, numPayments, requestAmount, collateralRatio, fundAmount);

        address fundingLocker = loan.fundingLocker();

        drawdownAmount = constrictToRange(drawdownAmount, 1 * USD, usdc.balanceOf(fundingLocker));
        uint256 collateralValue = drawdownAmount * loan.collateralRatio() / 10_000;

        uint256 reqCollateral = loan.collateralRequiredForDrawdown(drawdownAmount);
        withinDiff(reqCollateral * globals.getLatestPrice(WETH) * USD / WAD / 10 ** 8, collateralValue, 1);
    }

    function test_drawdown(
        uint256 apr,
        uint256 index,
        uint256 numPayments,
        uint256 requestAmount,
        uint256 collateralRatio,
        uint256 fundAmount,
        uint256 drawdownAmount
    )
        public
    {
        loan = instantiateAndFundLoan(apr, index, numPayments, requestAmount, collateralRatio, fundAmount);
        address fundingLocker = loan.fundingLocker();
        fundAmount = usdc.balanceOf(fundingLocker);

        drawdownAmount = constrictToRange(drawdownAmount, loan.requestAmount(), fundAmount, true);

        assertTrue(!b2.try_loan_drawdown(address(loan), drawdownAmount));                                   // Non-borrower can't drawdown
        if (loan.collateralRatio() > 0) assertTrue(!b1.try_loan_drawdown(address(loan), drawdownAmount));  // Can't drawdown without approving collateral

        uint256 reqCollateral = loan.collateralRequiredForDrawdown(drawdownAmount);
        mint(WETH, WETH_SLOT, address(b1), reqCollateral);
        b1.erc20_approve(WETH, address(loan), reqCollateral);

        assertTrue(!b1.try_loan_drawdown(address(loan), loan.requestAmount() - 1));  // Can't drawdown less than requestAmount
        assertTrue(!b1.try_loan_drawdown(address(loan),           fundAmount + 1));  // Can't drawdown more than fundingLocker balance

        uint256 pre = usdc.balanceOf(address(b1));

        assertEq(weth.balanceOf(address(b1)),  reqCollateral);  // Borrower collateral balance
        assertEq(usdc.balanceOf(fundingLocker),    fundAmount);  // FundingLocker liquidityAsset balance
        assertEq(usdc.balanceOf(address(loan)),             0);  // Loan liquidityAsset balance
        assertEq(loan.principalOwed(),                      0);  // Principal owed
        assertEq(uint256(loan.loanState()),                 0);  // Loan state: Ready

        // Fee related variables pre-check.
        assertEq(loan.feePaid(),                            0);  // feePaid amount
        assertEq(loan.excessReturned(),                     0);  // excessReturned amount
        assertEq(usdc.balanceOf(address(treasury)),         0);  // Treasury liquidityAsset balance

        // Pause protocol and attempt drawdown()
        assertTrue(globalAdmin.try_mapleGlobals_setProtocolPause(address(globals), true));
        assertTrue(!b1.try_loan_drawdown(address(loan), drawdownAmount));

        // Unpause protocol and drawdown()
        assertTrue(globalAdmin.try_mapleGlobals_setProtocolPause(address(globals), false));
        assertTrue(b1.try_loan_drawdown(address(loan), drawdownAmount));

        assertEq(weth.balanceOf(address(b1)),                                 0);  // Borrower collateral balance
        assertEq(weth.balanceOf(address(loan.collateralLocker())), reqCollateral);  // CollateralLocker collateral balance

        uint256 investorFee = drawdownAmount * globals.investorFee() / 10_000;
        uint256 treasuryFee = drawdownAmount * globals.treasuryFee() / 10_000;

        assertEq(usdc.balanceOf(fundingLocker),                                         0);  // FundingLocker liquidityAsset balance
        assertEq(usdc.balanceOf(address(loan)), fundAmount - drawdownAmount + investorFee);  // Loan liquidityAsset balance
        assertEq(loan.principalOwed(),                                     drawdownAmount);  // Principal owed
        assertEq(uint256(loan.loanState()),                                             1);  // Loan state: Active

        withinDiff(usdc.balanceOf(address(b1)), drawdownAmount - (investorFee + treasuryFee), 1); // Borrower liquidityAsset balance

        assertEq(loan.nextPaymentDue(), block.timestamp + loan.paymentIntervalSeconds());  // Next payment due timestamp calculated from time of drawdown

        // Fee related variables post-check.
        assertEq(loan.feePaid(),                                    investorFee);  // Drawdown amount
        assertEq(loan.excessReturned(),             fundAmount - drawdownAmount);  // Principal owed
        assertEq(usdc.balanceOf(address(treasury)),                 treasuryFee);  // Treasury loanAsset balance

        // Test FDT accounting
        address debtLocker = p1.debtLockers(address(loan), address(dlFactory));
        assertEq(IERC20(address(loan)).balanceOf(debtLocker), fundAmount * WAD / USD);
        withinDiff(IBasicFDT(address(loan)).withdrawableFundsOf(address(debtLocker)), fundAmount - drawdownAmount + investorFee, 1);

        // Can't drawdown() loan after it has already been called.
        assertTrue(!b1.try_loan_drawdown(address(loan), drawdownAmount));
    }

    function test_makePayment(
        uint256 apr,
        uint256 index,
        uint256 _numPayments,
        uint256 requestAmount,
        uint256 collateralRatio,
        uint256 fundAmount,
        uint256 drawdownAmount
    )
        public
    {
        loan = instantiateAndFundLoan(apr, index, _numPayments, requestAmount, collateralRatio, fundAmount);  // Const three payments used for this test
        fundAmount = usdc.balanceOf(loan.fundingLocker());

        drawdownAmount = constrictToRange(drawdownAmount, loan.requestAmount(), fundAmount, true);

        assertEq(uint256(loan.loanState()), 0);  // Loan state: Ready

        assertTrue(!b1.try_loan_makePayment(address(loan)));  // Can't makePayment when State != Active

        // Approve collateral and drawdown loan.
        uint256 reqCollateral = drawdown(loan, drawdownAmount);
        uint256 loanPreBal    = usdc.balanceOf(address(loan));  // Accounts for excess and fees from drawdown

        // NOTE: Do not need to hevm.warp in this test because payments can be made whenever as long as they are before the nextPaymentDue

        uint256 numPayments = loan.paymentsRemaining();
        // Approve 1st of 3 payments.
        (uint256 total, uint256 principal, uint256 interest, uint256 due,) = loan.getNextPayment();
        if (total == 0 && interest == 0) return;  // If fuzz params cause payments to be so small they round to zero, skip fuzz iteration

        assertTrue(!b1.try_loan_makePayment(address(loan)));  // Can't makePayment with lack of approval

        mint(USDC, USDC_SLOT, address(b1), total);
        b1.erc20_approve(USDC, address(loan), total);

        // Before state
        assertLoanState({
            loan_:             loan,
            loanState:         1,
            principalOwed:     drawdownAmount,
            principalPaid:     0,
            interestPaid:      0,
            loanBalance:       loanPreBal,
            paymentsRemaining: numPayments,
            nextPaymentDue:    due
        });

        // Pause protocol and attempt makePayment()
        assertTrue(globalAdmin.try_mapleGlobals_setProtocolPause(address(globals), true));
        assertTrue(!b1.try_loan_makePayment(address(loan)));

        // Unpause protocol and makePayment()
        assertTrue(globalAdmin.try_mapleGlobals_setProtocolPause(address(globals), false));
        assertTrue(b1.try_loan_makePayment(address(loan)));  // Make payment.

        due += loan.paymentIntervalSeconds();  // Increment next payment due by interval

        // After state
        assertLoanState({
            loan_:             loan,
            loanState:         1,
            principalOwed:     drawdownAmount,
            principalPaid:     0,
            interestPaid:      interest,
            loanBalance:       loanPreBal + interest,
            paymentsRemaining: numPayments - 1,
            nextPaymentDue:    due
        });

        // Approve numPayments - 1.
        for (uint256 i = 2; i <= numPayments - 1; i++) {
            repetitivePayment(loan, numPayments, i, drawdownAmount, loanPreBal, uint256(0));
        }
        
        // Approve last payment.
        (total, principal, interest, due,) = loan.getNextPayment();
        mint(USDC, USDC_SLOT, address(b1), total);
        b1.erc20_approve(USDC, address(loan), total);

        // Check CollateralLocker balance.
        assertEq(weth.balanceOf(loan.collateralLocker()), reqCollateral);

        // Make last payment.
        assertTrue(b1.try_loan_makePayment(address(loan)));

        due += loan.paymentIntervalSeconds();  // Increment next payment due by interval

        // After state, state variables.
        assertLoanState({
            loan_:             loan,
            loanState:         2,
            principalOwed:     0,
            principalPaid:     principal,
            interestPaid:      interest * numPayments,
            loanBalance:       loanPreBal + interest * numPayments + principal,
            paymentsRemaining: 0,
            nextPaymentDue:    0
        });

        // CollateralLocker after state.
        assertEq(weth.balanceOf(loan.collateralLocker()),            0);
        assertEq(weth.balanceOf(address(b1)),            reqCollateral);
    }

    function test_makePayment_late(
        uint256 apr,
        uint256 index,
        uint256 numPayments_,
        uint256 requestAmount,
        uint256 collateralRatio,
        uint256 fundAmount,
        uint256 drawdownAmount
    )
        public
    {
        loan = instantiateAndFundLoan(apr, index, numPayments_, requestAmount, collateralRatio, fundAmount);  // Const three payments used for this test
        address fundingLocker = loan.fundingLocker();
        fundAmount = usdc.balanceOf(fundingLocker);

        drawdownAmount = constrictToRange(drawdownAmount, loan.requestAmount(), fundAmount, true);

        assertEq(uint256(loan.loanState()), 0);  // Loan state: Ready

        assertTrue(!b1.try_loan_makePayment(address(loan)));  // Can't makePayment when State != Active

        // Approve collateral and drawdown loan.
        uint256 reqCollateral = drawdown(loan, drawdownAmount);
        uint256 loanPreBal    = usdc.balanceOf(address(loan));  // Accounts for excess and fees from drawdown
        uint256 numPayments   = loan.paymentsRemaining();

        // Approve 1st of 3 payments.
        (uint256 total, uint256 principal, uint256 interest, uint256 due,) = loan.getNextPayment();
        if (total == 0 && interest == 0) return;  // If fuzz params cause payments to be so small they round to zero, skip fuzz iteration

        assertTrue(!b1.try_loan_makePayment(address(loan)));  // Can't makePayment with lack of approval

        mint(USDC, USDC_SLOT, address(b1), total);
        b1.erc20_approve(USDC, address(loan), total);

        // Before state
        assertLoanState({
            loan_:             loan,
            loanState:         1,
            principalOwed:     drawdownAmount,
            principalPaid:     0,
            interestPaid:      0,
            loanBalance:       loanPreBal,
            paymentsRemaining: numPayments,
            nextPaymentDue:    due
        });

        // Make first payment on time.
        assertTrue(b1.try_loan_makePayment(address(loan)));

        due += loan.paymentIntervalSeconds();  // Increment next payment due by interval

        // After state
        assertLoanState({
            loan_:             loan,
            loanState:         1,
            principalOwed:     drawdownAmount,
            principalPaid:     0,
            interestPaid:      interest,
            loanBalance:       loanPreBal + interest,
            paymentsRemaining: numPayments - 1,
            nextPaymentDue:    due
        });

        // Approve numPayments - 1.
        for (uint256 i = 1; i < numPayments - 1; i++) {
            // Warp to 1 second after next payment is due (payment is late)
            hevm.warp(loan.nextPaymentDue() + 1);
            repetitivePayment(loan, numPayments, i, drawdownAmount, loanPreBal, interest);
        }

        uint256 interest_late;

        // Warp to 1 second after next payment is due (payment is late)
        hevm.warp(loan.nextPaymentDue() + 1);

        // Approve 3nd of 3 payments.
        (total, principal, interest_late, due,) = loan.getNextPayment();
        mint(USDC, USDC_SLOT, address(b1), total);
        b1.erc20_approve(USDC, address(loan), total);

        // Check CollateralLocker balance.
        assertEq(weth.balanceOf(loan.collateralLocker()), reqCollateral);

        // Make payment.
        assertTrue(b1.try_loan_makePayment(address(loan)));

        due += loan.paymentIntervalSeconds();  // Increment next payment due by interval

        // After state, state variables.
        assertLoanState({
            loan_:             loan,
            loanState:         2,
            principalOwed:     0,
            principalPaid:     principal,
            interestPaid:      interest + interest_late * (numPayments - 1),
            loanBalance:       loanPreBal + interest + interest_late * (numPayments - 1) + principal,
            paymentsRemaining: 0,
            nextPaymentDue:    0
        });

        // CollateralLocker after state.
        assertEq(weth.balanceOf(loan.collateralLocker()),             0);
        assertEq(weth.balanceOf(address(b1)),            reqCollateral);
    }

    function test_unwind_loan(
        uint256 apr,
        uint256 index,
        uint256 numPayments_,
        uint256 requestAmount,
        uint256 collateralRatio,
        uint256 fundAmount,
        uint256 drawdownAmount
    )
        public
    {
        loan = instantiateAndFundLoan(apr, index, numPayments_, requestAmount, collateralRatio, fundAmount);  // Const three payments used for this test
        address fundingLocker = loan.fundingLocker();
        fundAmount = usdc.balanceOf(fundingLocker);

        // Warp to the fundingPeriod, can't call unwind() yet
        hevm.warp(loan.createdAt() + globals.fundingPeriod());
        assertTrue(!pd1.try_loan_unwind(address(loan)));

        uint256 flBalancePre   = usdc.balanceOf(fundingLocker);
        uint256 loanBalancePre = usdc.balanceOf(address(loan));
        uint256 loanStatePre   = uint256(loan.loanState());

        assertEq(flBalancePre, fundAmount);
        assertEq(loanStatePre, 0);

        // Warp 1 more second, can call unwind()
        hevm.warp(loan.createdAt() + globals.fundingPeriod() + 1);

        // Pause protocol and attempt unwind()
        assertTrue(globalAdmin.try_mapleGlobals_setProtocolPause(address(globals), true));
        assertTrue(!pd1.try_loan_unwind(address(loan)));

        // Unpause protocol and unwind()
        assertTrue(globalAdmin.try_mapleGlobals_setProtocolPause(address(globals), false));
        assertTrue(pd1.try_loan_unwind(address(loan)));

        uint256 flBalancePost   = usdc.balanceOf(fundingLocker);
        uint256 loanBalancePost = usdc.balanceOf(address(loan));
        uint256 loanStatePost   = uint256(loan.loanState());

        assertEq(flBalancePost, 0);
        assertEq(loanStatePost, 3);

        assertEq(flBalancePre,    fundAmount);
        assertEq(loanBalancePost, fundAmount);

        assertEq(loan.excessReturned(), loanBalancePost);

        // Pause protocol and attempt withdrawFunds() (through claim)
        assertTrue(globalAdmin.try_mapleGlobals_setProtocolPause(address(globals), true));
        assertTrue(!pd1.try_pool_claim(address(p1), address(loan), address(dlFactory)));

        // Unpause protocol and withdrawFunds() (through claim)
        assertTrue(globalAdmin.try_mapleGlobals_setProtocolPause(address(globals), false));
        assertTrue(pd1.try_pool_claim(address(p1), address(loan), address(dlFactory)));

        withinDiff(usdc.balanceOf(address(p1.liquidityLocker())), fundAmount, 1);
        withinDiff(usdc.balanceOf(address(loan)),                            0, 1);

        // Can't unwind() loan after it has already been called.
        assertTrue(!pd1.try_loan_unwind(address(loan)));
    }

    function test_trigger_default(
        uint256 apr,
        uint256 index,
        uint256 numPayments_,
        uint256 requestAmount,
        uint256 collateralRatio,
        uint256 fundAmount,
        uint256 drawdownAmount
    )
        public
    {
        gov.mapleGlobals_setMaxSwapSlippage(address(globals), 10_000);  // Set 100% slippage to account for very large liquidations from fuzzing

        loan = instantiateAndFundLoan(apr, index, numPayments_, requestAmount, collateralRatio, fundAmount);
        address fundingLocker = loan.fundingLocker();
        fundAmount = IERC20(USDC).balanceOf(fundingLocker);
        uint256 wadAmount = fundAmount * WAD / USD;

        drawdownAmount = constrictToRange(drawdownAmount, loan.requestAmount(), fundAmount, true);

        address debtLocker = p1.debtLockers(address(loan), address(dlFactory));

        assertEq(uint256(loan.loanState()), 0);  // `Ready` state

        uint256 reqCollateral = drawdown(loan, drawdownAmount);

        assertEq(uint256(loan.loanState()), 1);  // `Active` state

        assertTrue(!pd1.try_pool_triggerDefault(address(p1), address(loan), address(dlFactory)));  // Should fail to trigger default because current time is still less than the `nextPaymentDue`.
        assertTrue( !ex.try_loan_triggerDefault(address(loan)));                                    // Failed because commoner in not allowed to default the loan because they do not own any LoanFDTs.

        hevm.warp(loan.nextPaymentDue() + 1);

        assertTrue(!pd1.try_pool_triggerDefault(address(p1), address(loan), address(dlFactory)));  // Failed because still loan has defaultGracePeriod to repay the dues.
        assertTrue( !ex.try_loan_triggerDefault(address(loan)));                                    // Failed because still commoner is not allowed to default the loan.

        hevm.warp(loan.nextPaymentDue() + globals.defaultGracePeriod());

        assertTrue(!pd1.try_pool_triggerDefault(address(p1), address(loan), address(dlFactory)));  // Failed because still loan has defaultGracePeriod to repay the dues.
        assertTrue( !ex.try_loan_triggerDefault(address(loan)));                                   // Failed because still commoner is not allowed to default the loan.

        hevm.warp(loan.nextPaymentDue() + globals.defaultGracePeriod() + 1);

        assertTrue(!ex.try_loan_triggerDefault(address(loan)));                                   // Failed because still commoner is not allowed to default the loan.

        // Sid's Pool currently has 100% of LoanFDTs, so he can trigger the loan default.
        // For this test, minLoanEquity is transferred to the commoner to test the minimum loan equity condition.
        assertEq(IERC20(address(loan)).totalSupply(), wadAmount);
        assertEq(globals.minLoanEquity(),             2000);  // 20%

        uint256 minEquity = IERC20(address(loan)).totalSupply() * globals.minLoanEquity() / 10_000;

        // Simulate transfer of LoanFDTs from DebtLocker to commoner (<20% of total supply)
        hevm.store(
            address(loan),
            keccak256(abi.encode(address(ex), 0)), // Mint tokens
            bytes32(uint256(minEquity - 1))
        );
        hevm.store(
            address(loan),
            keccak256(abi.encode(address(debtLocker), 0)), // Overwrite balance
            bytes32(uint256(wadAmount - minEquity + 1))
        );

        assertTrue(!ex.try_loan_triggerDefault(address(loan)));  // Failed because still commoner is not allowed to default the loan.

        // "Transfer" 1 more wei to meet 20% minimum equity requirement
        hevm.store(
            address(loan),
            keccak256(abi.encode(address(ex), 0)), // Mint tokens
            bytes32(uint256(minEquity))
        );
        hevm.store(
            address(loan),
            keccak256(abi.encode(address(debtLocker), 0)), // Overwrite balance
            bytes32(uint256(wadAmount - minEquity))
        );

        assertTrue(ex.try_loan_triggerDefault(address(loan)));  // Now with 20% of loan equity, a loan can be defaulted
        assertEq(uint256(loan.loanState()), 4);
    }

    function test_calc_min_amount(
        uint256 apr,
        uint256 index,
        uint256 requestAmount,
        uint256 collateralRatio,
        uint256 fundAmount,
        uint256 drawdownAmount
    )
        public
    {
        loan = instantiateAndFundLoan(apr, index, 3, requestAmount, collateralRatio, fundAmount);  // Const three payments used for this test
        address fundingLocker = loan.fundingLocker();
        fundAmount = IERC20(USDC).balanceOf(fundingLocker);

        drawdownAmount = constrictToRange(drawdownAmount, loan.requestAmount(), fundAmount, true);

        uint256 reqCollateral = drawdown(loan, drawdownAmount);

        uint256 expectedAmount = (reqCollateral * globals.getLatestPrice(WETH)) / globals.getLatestPrice(USDC);

        assertEq((expectedAmount * USD) / WAD, loan.getExpectedAmountRecovered());
    }

    function test_makeFullPayment(
        uint256 apr,
        uint256 index,
        uint256 numPayments,
        uint256 requestAmount,
        uint256 collateralRatio,
        uint256 fundAmount,
        uint256 drawdownAmount
    )
        public
    {
        loan = instantiateAndFundLoan(apr, index, numPayments, requestAmount, collateralRatio, fundAmount);
        fundAmount = usdc.balanceOf(loan.fundingLocker());

        drawdownAmount = constrictToRange(drawdownAmount, loan.requestAmount(), fundAmount, true);

        assertEq(uint256(loan.loanState()), 0);  // Loan state: Ready

        assertTrue(!b1.try_loan_makeFullPayment(address(loan)));  // Can't makePayment when State != Active

        // Approve collateral and drawdown loan.
        uint256 reqCollateral = drawdown(loan, drawdownAmount);
        uint256 loanPreBal    = usdc.balanceOf(address(loan));

        assertTrue(!b1.try_loan_makeFullPayment(address(loan)));  // Can't makePayment with lack of approval

        // Approve full payment.
        (uint256 total, uint256 principal, uint256 interest) = loan.getFullPayment();
        mint(USDC, USDC_SLOT, address(b1), total);
        b1.erc20_approve(USDC, address(loan), total);

        // Before state
        assertLoanState({
            loan_:             loan,
            loanState:         1,
            principalOwed:     drawdownAmount,
            principalPaid:     0,
            interestPaid:      0,
            loanBalance:       loanPreBal,
            paymentsRemaining: loan.paymentsRemaining(),
            nextPaymentDue:    block.timestamp + loan.paymentIntervalSeconds()  // Not relevant to full payment
        });

        // CollateralLocker before state.
        assertEq(weth.balanceOf(loan.collateralLocker()), reqCollateral);
        assertEq(weth.balanceOf(address(b1)),                 0);

        // Pause protocol and attempt makeFullPayment()
        assertTrue(globalAdmin.try_mapleGlobals_setProtocolPause(address(globals), true));
        assertTrue(!b1.try_loan_makeFullPayment(address(loan)));

        // Unpause protocol and makeFullPayment()
        assertTrue(globalAdmin.try_mapleGlobals_setProtocolPause(address(globals), false));
        assertTrue(b1.try_loan_makeFullPayment(address(loan)));  // Make full payment.

        // After state
        assertEq(usdc.balanceOf(address(loan)), loanPreBal + total);

        assertLoanState({
            loan_:             loan,
            loanState:         2,
            principalOwed:     0,
            principalPaid:     principal,
            interestPaid:      interest,
            loanBalance:       loanPreBal + interest + principal,
            paymentsRemaining: 0,
            nextPaymentDue:    0
        });

        // CollateralLocker after state.
        assertEq(weth.balanceOf(loan.collateralLocker()),             0);
        assertEq(weth.balanceOf(address(b1)),     reqCollateral);
    }

    function test_reclaim_erc20() external {
        loan = instantiateAndFundLoan(2, 10, 5, 100000, 20, 1000000);
        // Add different kinds of assets to the loan.
        mint(USDC, USDC_SLOT, address(loan), 1000 * USD);
        mint(DAI,  DAI_SLOT,  address(loan), 1000 * WAD);
        mint(WETH, WETH_SLOT, address(loan),  100 * WAD);

        Governor fakeGov = new Governor();

        uint256 beforeBalanceDAI  =  dai.balanceOf(address(gov));
        uint256 beforeBalanceWETH = weth.balanceOf(address(gov));

        assertTrue(!fakeGov.try_loan_reclaimERC20(address(loan), DAI));
        assertTrue(    !gov.try_loan_reclaimERC20(address(loan), USDC));  // Governor cannot remove liquidityAsset from loans
        assertTrue(    !gov.try_loan_reclaimERC20(address(loan), address(0)));
        assertTrue(     gov.try_loan_reclaimERC20(address(loan), WETH));
        assertTrue(     gov.try_loan_reclaimERC20(address(loan), DAI));

        uint256 afterBalanceDAI  =  dai.balanceOf(address(gov));
        uint256 afterBalanceWETH = weth.balanceOf(address(gov));

        assertEq(afterBalanceDAI  - beforeBalanceDAI,  1000 * WAD);
        assertEq(afterBalanceWETH - beforeBalanceWETH,  100 * WAD);
    }

    function test_setLoanAdmin() public {
        address newLoanAdmin = address(new GlobalAdmin());
        loan = instantiateAndFundLoan(2, 10, 5, 100000, 20, 1000000);
        // Pause protocol and attempt setLoanAdmin()
        assertTrue(globalAdmin.try_mapleGlobals_setProtocolPause(address(globals), true));
        assertTrue(!b1.try_loan_setLoanAdmin(address(loan), newLoanAdmin, true));
        assertTrue(!loan.loanAdmins(newLoanAdmin));

        // Unpause protocol and setLoanAdmin()
        assertTrue(globalAdmin.try_mapleGlobals_setProtocolPause(address(globals), false));
        assertTrue(b1.try_loan_setLoanAdmin(address(loan), newLoanAdmin, true));
        assertTrue(loan.loanAdmins(newLoanAdmin));
    }

    function repetitivePayment(ILoan loan_, uint256 numPayments, uint256 paymentCount, uint256 drawdownAmount, uint256 loanPreBal, uint256 oldInterest) internal {
        (uint256 total,, uint256 interest, uint256 due,) = loan_.getNextPayment();
        mint(USDC, USDC_SLOT, address(b1), total);
        b1.erc20_approve(USDC, address(loan_), total);

        // Below is the way of catering two scenarios
        // 1. When there is no late payment so interest paid will be a multiple of `numPayments`.
        // 2. If there is a late payment then needs to handle the situation where interest paid is `interest (without late fee) + interest (late fee) * numPayments`.
        numPayments = oldInterest == uint256(0) ? numPayments - paymentCount : numPayments - paymentCount - 1;
        // Make payment.
        assertTrue(b1.try_loan_makePayment(address(loan_)));

        due += loan_.paymentIntervalSeconds();  // Increment next payment due by interval

        // After state
        assertLoanState({
            loan_:             loan_,
            loanState:         1,
            principalOwed:     drawdownAmount,
            principalPaid:     0,
            interestPaid:      oldInterest + (interest * paymentCount),
            loanBalance:       loanPreBal  + oldInterest + (interest * paymentCount),
            paymentsRemaining: numPayments,
            nextPaymentDue:    due
        });
    }

}
