// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

// TODO: fix erc20_mint, since StateManipulations and TestUtils both have hevm

import { IERC20 }   from "../../modules/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { Pausable } from "../../modules/openzeppelin-contracts/contracts/utils/Pausable.sol";

import { TestUtils, StateManipulations } from "../../modules/contract-test-utils/contracts/test.sol";

import { IBFactoryLike, IBPoolLike } from "./interfaces/Interfaces.sol";

import { LoanUser }          from "../../modules/loan/contracts/test/accounts/LoanUser.sol";
import { GlobalAdmin }       from "./accounts/GlobalAdmin.sol";
import { Governor }          from "./accounts/Governor.sol";
import { Borrower }          from "./accounts/Borrower.sol";
import { PoolDelegate }      from "./accounts/PoolDelegate.sol";
import { LiquidityProvider } from "./accounts/LiquidityProvider.sol";
import { Explorer }          from "./accounts/Explorer.sol";

import { IMapleGlobals, MapleGlobals }                       from "../../modules/globals/contracts/MapleGlobals.sol";
import { ILoanFactory, LoanFactory }                         from "../../modules/loan/contracts/LoanFactory.sol";
import { ILoan, Loan }                                       from "../../modules/loan/contracts/Loan.sol";
import { IPoolFactory, PoolFactory }                         from "../../modules/pool/contracts/PoolFactory.sol";
import { IPool, Pool }                                       from "../../modules/pool/contracts/Pool.sol";
import { IFundingLockerFactory, FundingLockerFactory }       from "../../modules/funding-locker/contracts/FundingLockerFactory.sol";
import { ICollateralLockerFactory, CollateralLockerFactory } from "../../modules/collateral-locker/contracts/CollateralLockerFactory.sol";
import { IStakeLockerFactory, StakeLockerFactory }           from "../../modules/stake-locker/contracts/StakeLockerFactory.sol";
import { IStakeLocker, StakeLocker }                         from "../../modules/stake-locker/contracts/StakeLocker.sol";
import { ILiquidityLockerFactory, LiquidityLockerFactory }   from "../../modules/liquidity-locker/contracts/LiquidityLockerFactory.sol";
import { ILateFeeCalc, LateFeeCalc }                         from "../../modules/late-fee-calculator/contracts/LateFeeCalc.sol";
import { IRepaymentCalc, RepaymentCalc }                     from "../../modules/repayment-calculator/contracts/RepaymentCalc.sol";
import { IPremiumCalc, PremiumCalc }                         from "../../modules/premium-calculator/contracts/PremiumCalc.sol";
import { IDebtLockerFactory, DebtLockerFactory }             from "../../modules/debt-locker/contracts/DebtLockerFactory.sol";
import { IChainlinkOracle, ChainlinkOracle }                 from "../../modules/chainlink-oracle/contracts/ChainlinkOracle.sol";
import { IUsdOracle, UsdOracle }                             from "../../modules/usd-oracle/contracts/UsdOracle.sol";
import { IMapleTreasury, MapleTreasury }                     from "../../modules/treasury/contracts/MapleTreasury.sol";

contract LoanTestUtil is TestUtils, StateManipulations {

    uint256 constant MAX_UINT   = type(uint256).max;
    uint256 constant USDC_SCALE = 0;  // TODO: fix
    uint256 constant WAD_SCALE  = 0;  // TODO: fix

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

    // Setup for loan creation - 

    // 1. Deploy funding locker factory
    // 2. Deploy collateral locker factory.
    // 3. Deploy the globalAdmin. 
    // 4. Deploy the globals.  -- Use already deployed MPL address.
    // 5. Deploy the loan factory.
    // 6. whitelist the L, FL & CL factory with globals.

    function validateFactories(
        address globals,
        Governor governor,
        address loanFactory,
        address poolFactory,
        address collateralLockerFactory,
        address fundingLockerFactory,
        address stakeLockerFactory,
        address liquidityLockerFactory,
        address debtLockerFactory
    )
        public
    {
        governor.mapleGlobals_setValidLoanFactory(globals, loanFactory, true);

        governor.mapleGlobals_setValidPoolFactory(globals, poolFactory, true);

        governor.mapleGlobals_setValidSubFactory(globals, loanFactory, collateralLockerFactory, true);
        governor.mapleGlobals_setValidSubFactory(globals, loanFactory, fundingLockerFactory, true);
        governor.mapleGlobals_setValidSubFactory(globals, poolFactory, stakeLockerFactory, true);
        governor.mapleGlobals_setValidSubFactory(globals, poolFactory, liquidityLockerFactory, true);
        governor.mapleGlobals_setValidSubFactory(globals, poolFactory, debtLockerFactory, true);
    }

    function deployBalancerPool(
        address globals,
        address tokenA,
        uint256 slotA,
        uint256 amountA,
        address tokenB,
        uint256 slotB,
        uint256 amountB,
        Governor governor
    )
        public returns (address bPool)
    {
        // Mint USDC into this account
        erc20_mint(tokenA, slotA, address(this), amountA);
        erc20_mint(tokenB, slotB, address(this), amountB);

        // Initialize MPL/USDC Balancer Pool and whitelist
        bPool = IBFactoryLike(BPOOL_FACTORY).newBPool();

        IERC20(tokenA).approve(bPool, MAX_UINT);
        IERC20(tokenB).approve(bPool, MAX_UINT);

        IBPoolLike(bPool).bind(tokenA, amountA, 5 ether);  // Bind USDC with 5 denormalization weight
        IBPoolLike(bPool).bind(tokenB, amountB, 5 ether);  // Bind  MPL with 5 denormalization weight

        IBPoolLike(bPool).finalize();

        governor.mapleGlobals_setValidBalancerPool(globals, bPool, true);
    }

    function stakeAndFinalizePool(uint256 stakeAmount, address pool, PoolDelegate poolDelegate, address bPool) public {
        address stakeLocker = IPool(pool).stakeLocker();

        poolDelegate.erc20_approve(bPool, stakeLocker, MAX_UINT);
        poolDelegate.stakeLocker_stake(stakeLocker, stakeAmount);
        poolDelegate.pool_finalize(pool);
        poolDelegate.pool_setOpenToPublic(pool, true);
    }

    function deployPool(
        PoolDelegate poolDelegate,
        address poolFactory,
        address liquidityAsset,
        address stakeAsset,
        address stakeLockerFactory,
        address liquidityLockerFactory
    )
        public returns (address pool)
    {
        return poolDelegate.poolFactory_createPool(
            poolFactory,
            liquidityAsset,
            stakeAsset,
            stakeLockerFactory,
            liquidityLockerFactory,
            500,
            500,
            MAX_UINT
        );
    }

    function getFuzzedSpecs(
        uint256 apr,
        uint256 index,             // Random index for random payment interval
        uint256 numPayments,       // Used for termDays
        uint256 requestAmount,
        uint256 collateralRatio
    ) public pure returns (uint256[5] memory) {
        return getFuzzedSpecs(apr, index, numPayments, requestAmount, collateralRatio, 10_000 * USDC_SCALE, 10_000, 1e10 * USDC_SCALE);
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
    ) public pure returns (uint256[5] memory) {
        uint16[10] memory paymentIntervalArray = [1, 2, 5, 7, 10, 15, 30, 60, 90, 360];
        numPayments = constrictToRange(numPayments, 5, 100);
        uint256 paymentIntervalDays = paymentIntervalArray[index % 10];  // TODO: Consider changing this approach
        uint256 termDays            = paymentIntervalDays * numPayments;

        return [
            constrictToRange(apr, 1, 10_000),                                   // APR between 0.01% and 100% (non-zero for test behavior)
            termDays,                                                                 // Fuzzed term days
            paymentIntervalDays,                                                      // Payment interval days from array
            constrictToRange(requestAmount, minimumRequestAmt, maxRequestAmt),  // 10k USD - 10b USD loans (non-zero) in general scenario
            constrictToRange(collateralRatio, 0, maxCollateralRatio)                  // Collateral ratio between 0 and maxCollateralRatio
        ];
    }

}

contract LoanTest is LoanTestUtil {

    IBPoolLike bPool;

    Governor governor;
    Loan loan;
    MapleGlobals globals;
    LoanFactory loanFactory;
    PoolFactory poolFactory;
    CollateralLockerFactory collateralLockerFactory;
    FundingLockerFactory fundingLockerFactory;
    StakeLockerFactory stakeLockerFactory;
    LiquidityLockerFactory liquidityLockerFactory;
    DebtLockerFactory debtLockerFactory;
    LateFeeCalc lateFeeCalc;
    RepaymentCalc repaymentCalc;
    PremiumCalc premiumCalc;
    ChainlinkOracle wethOracle;
    UsdOracle usdOracle;
    MapleTreasury treasury;

    Pool pool1;
    Pool pool2;
    PoolDelegate poolDelegate1;
    PoolDelegate poolDelegate2;
    GlobalAdmin globalAdmin;
    Explorer explorer;

    LiquidityProvider liquidityProvider1;
    LiquidityProvider liquidityProvider2;

    Borrower borrower1;
    Borrower borrower2;

    address securityAdmin = address(this);

    function setUp() public {
        governor           = new Governor();
        poolDelegate1      = new PoolDelegate();
        poolDelegate2      = new PoolDelegate();
        borrower1          = new Borrower();
        borrower2          = new Borrower();
        liquidityProvider1 = new LiquidityProvider();
        liquidityProvider2 = new LiquidityProvider();
        explorer           = new Explorer();

        globalAdmin = new GlobalAdmin();
        globals = new MapleGlobals(address(governor), MPL, address(globalAdmin));

        treasury = new MapleTreasury(MPL, USDC, UNISWAP_V2_ROUTER_02, address(globals)); 
        governor.mapleGlobals_setMapleTreasury(address(globals), address(treasury));

        wethOracle = new ChainlinkOracle(WETH_AGGREGATOR, WETH, securityAdmin);
        usdOracle  = new UsdOracle();

        governor.mapleGlobals_setPriceOracle(address(globals), WETH, address(wethOracle));
        governor.mapleGlobals_setPriceOracle(address(globals), USDC, address(usdOracle));

        loanFactory = new LoanFactory(address(globals));
        poolFactory = new PoolFactory(address(globals));

        collateralLockerFactory = new CollateralLockerFactory();
        fundingLockerFactory = new FundingLockerFactory();


        stakeLockerFactory = new StakeLockerFactory();
        liquidityLockerFactory = new LiquidityLockerFactory();
        debtLockerFactory = new DebtLockerFactory();

        bPool = IBPoolLike(deployBalancerPool(
            address(globals),
            USDC,
            USDC_SLOT,
            1_550_000 * USDC_SCALE,
            MPL,
            MPL_SLOT,
            155_000 * WAD_SCALE,
            governor
        ));

        governor.mapleGlobals_setCalc(address(globals), address(lateFeeCalc = new LateFeeCalc(5)),    true);
        governor.mapleGlobals_setCalc(address(globals), address(premiumCalc = new PremiumCalc(500)),  true);
        governor.mapleGlobals_setCalc(address(globals), address(repaymentCalc = new RepaymentCalc()), true);

        governor.mapleGlobals_setPoolDelegateAllowlist(address(globals), address(poolDelegate1), true);
        governor.mapleGlobals_setPoolDelegateAllowlist(address(globals), address(poolDelegate2), true);

        governor.mapleGlobals_setLiquidityAsset(address(globals), USDC, true);

        governor.mapleGlobals_setCollateralAsset(address(globals), USDC, true);
        governor.mapleGlobals_setCollateralAsset(address(globals), WETH, true);

        validateFactories(
            address(globals),
            governor,
            address(loanFactory),
            address(poolFactory),
            address(collateralLockerFactory),
            address(fundingLockerFactory),
            address(stakeLockerFactory),
            address(liquidityLockerFactory),
            address(debtLockerFactory)
        );

        // Pool 1 setup
        pool1 = Pool(deployPool(poolDelegate1, address(poolFactory), USDC, address(bPool), address(stakeLockerFactory), address(liquidityLockerFactory)));
        bPool.transfer(address(poolDelegate1), 50 * WAD_SCALE);
        stakeAndFinalizePool(bPool.balanceOf(address(poolDelegate1)), address(pool1), poolDelegate1, address(bPool));

        // Pool 2 setup
        pool2 = Pool(deployPool(poolDelegate2, address(poolFactory), USDC, address(bPool), address(stakeLockerFactory), address(liquidityLockerFactory)));
        bPool.transfer(address(poolDelegate2), 50 * WAD_SCALE);
        stakeAndFinalizePool(bPool.balanceOf(address(poolDelegate2)), address(pool2), poolDelegate2, address(bPool));
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

        loan = Loan(borrower1.loanFactory_createLoan(address(loanFactory), USDC, WETH, address(fundingLockerFactory), address(collateralLockerFactory), specs, calcs));

        address fundingLocker   = loan.fundingLocker();
        address liquidityLocker = pool1.liquidityLocker();

        fundAmount = constrictToRange(fundAmount, 1 * USDC_SCALE, 1E10 * USDC_SCALE);
        uint256 wadAmount = fundAmount * WAD_SCALE / USDC_SCALE;

        fundAmount2 = constrictToRange(fundAmount, 1 * USDC_SCALE, 1E10 * USDC_SCALE);
        uint256 wadAmount2 = fundAmount2 * WAD_SCALE / USDC_SCALE;

        erc20_mint(USDC, USDC_SLOT, address(liquidityProvider1), (fundAmount + fundAmount2));
        liquidityProvider1.erc20_approve(USDC, address(pool1), (fundAmount + fundAmount2));
        liquidityProvider1.pool_deposit(address(pool1), (fundAmount + fundAmount2));

        // Note: Cannot do pre-state check for LoanFDT balance of debtLocker since it is not instantiated
        assertEq(IERC20(USDC).balanceOf(fundingLocker),                            0);
        assertEq(IERC20(USDC).balanceOf(liquidityLocker), (fundAmount + fundAmount2));

        // Loan-specific pause by Borrower
        assertTrue(!loan.paused());
        assertTrue(borrower1.try_loan_pause(address(loan)));
        assertTrue(loan.paused());
        assertTrue(!poolDelegate1.try_pool_fundLoan(address(pool1), address(loan), address(debtLockerFactory), fundAmount));  // Allow for two fundings

        assertTrue(borrower1.try_loan_unpause(address(loan)));
        assertTrue(!loan.paused());

        uint256 start = block.timestamp;

        hevm.warp(start + globals.fundingPeriod() + 1);  // Warp to past fundingPeriod, loan cannot be funded
        assertTrue(!poolDelegate1.try_pool_fundLoan(address(pool1), address(loan), address(debtLockerFactory), fundAmount));

        hevm.warp(start + globals.fundingPeriod());  // Warp to fundingPeriod, loan can be funded
        assertTrue(poolDelegate1.try_pool_fundLoan(address(pool1), address(loan), address(debtLockerFactory), fundAmount));

        address debtLocker = pool1.debtLockers(address(loan), address(debtLockerFactory));

        assertEq(loan.balanceOf(debtLocker), wadAmount);
        assertEq(IERC20(USDC).balanceOf(fundingLocker),              fundAmount);
        assertEq(IERC20(USDC).balanceOf(liquidityLocker),           fundAmount2);

        // Protocol-wide pause by Emergency Admin
        assertTrue(globalAdmin.try_mapleGlobals_setProtocolPause(address(globals), true));
        assertTrue(globals.protocolPaused());
        assertTrue(!poolDelegate1.try_pool_fundLoan(address(pool1), address(loan), address(debtLockerFactory), fundAmount2));

        assertTrue(globalAdmin.try_mapleGlobals_setProtocolPause(address(globals), false));
        assertTrue(!globals.protocolPaused());
        assertTrue(poolDelegate1.try_pool_fundLoan(address(pool1), address(loan), address(debtLockerFactory), fundAmount2));

        assertEq(loan.balanceOf(debtLocker),  wadAmount + wadAmount2);
        assertEq(IERC20(USDC).balanceOf(fundingLocker),                fundAmount + fundAmount2);
        assertEq(IERC20(USDC).balanceOf(liquidityLocker),              0);
    }

    function instantiateAndFundLoan(
        uint256 apr,
        uint256 index,
        uint256 numPayments,
        uint256 requestAmount,
        uint256 collateralRatio,
        uint256 fundAmount
    )
        internal returns (Loan _loan)
    {
        uint256[5] memory specs = getFuzzedSpecs(apr, index, numPayments, requestAmount, collateralRatio);
        address[3] memory calcs = [address(repaymentCalc), address(lateFeeCalc), address(premiumCalc)];

        _loan = Loan(borrower1.loanFactory_createLoan(address(loanFactory), USDC, WETH, address(fundingLockerFactory), address(collateralLockerFactory), specs, calcs));

        fundAmount = constrictToRange(fundAmount, specs[3], 1e10 * USDC_SCALE);  // Fund between requestAmount and 10b USD

        erc20_mint(USDC, USDC_SLOT, address(liquidityProvider1), fundAmount);
        liquidityProvider1.erc20_approve(USDC, address(pool1),      fundAmount);
        liquidityProvider1.pool_deposit(address(pool1),       fundAmount);

        poolDelegate1.pool_fundLoan(address(pool1), address(_loan), address(debtLockerFactory), fundAmount);
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
        assertEq(IERC20(USDC).balanceOf(address(loan_)),       loanBalance);
        assertEq(loan_.paymentsRemaining(),      paymentsRemaining);
        assertEq(loan_.nextPaymentDue(),            nextPaymentDue);
    }

    function drawdown(ILoan loan_, uint256 drawdownAmount) internal returns (uint256 requiredCollateral) {
        requiredCollateral = loan_.collateralRequiredForDrawdown(drawdownAmount);
        erc20_mint(WETH, WETH_SLOT, address(borrower1), requiredCollateral);
        borrower1.erc20_approve(WETH, address(loan_), requiredCollateral);
        assertTrue(borrower1.try_loan_drawdown(address(loan_), drawdownAmount));  // Borrow draws down on loan
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

        drawdownAmount = constrictToRange(drawdownAmount, 1 * USDC_SCALE, IERC20(USDC).balanceOf(fundingLocker));
        uint256 collateralValue = drawdownAmount * loan.collateralRatio() / 10_000;

        uint256 reqCollateral = loan.collateralRequiredForDrawdown(drawdownAmount);
        assertWithinDiff(reqCollateral * globals.getLatestPrice(WETH) * USDC_SCALE / WAD_SCALE / 10 ** 8, collateralValue, 1);
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
        fundAmount = IERC20(USDC).balanceOf(fundingLocker);

        drawdownAmount = constrictToRange(drawdownAmount, loan.requestAmount(), fundAmount);

        assertTrue(!borrower2.try_loan_drawdown(address(loan), drawdownAmount));                                   // Non-borrower can't drawdown

        if (loan.collateralRatio() > 0) assertTrue(!borrower1.try_loan_drawdown(address(loan), drawdownAmount));  // Can't drawdown without approving collateral

        uint256 reqCollateral = loan.collateralRequiredForDrawdown(drawdownAmount);
        erc20_mint(WETH, WETH_SLOT, address(borrower1), reqCollateral);
        borrower1.erc20_approve(WETH, address(loan), reqCollateral);

        assertTrue(!borrower1.try_loan_drawdown(address(loan), loan.requestAmount() - 1));  // Can't drawdown less than requestAmount
        assertTrue(!borrower1.try_loan_drawdown(address(loan),           fundAmount + 1));  // Can't drawdown more than fundingLocker balance

        uint256 pre = IERC20(USDC).balanceOf(address(borrower1));

        assertEq(IERC20(WETH).balanceOf(address(borrower1)),  reqCollateral);  // Borrower collateral balance
        assertEq(IERC20(USDC).balanceOf(fundingLocker),    fundAmount);  // FundingLocker liquidityAsset balance
        assertEq(IERC20(USDC).balanceOf(address(loan)),             0);  // Loan liquidityAsset balance
        assertEq(loan.principalOwed(),                      0);  // Principal owed
        assertEq(uint256(loan.loanState()),                 0);  // Loan state: Ready

        // Fee related variables pre-check.
        assertEq(loan.feePaid(),                            0);  // feePaid amount
        assertEq(loan.excessReturned(),                     0);  // excessReturned amount
        assertEq(IERC20(USDC).balanceOf(address(treasury)),         0);  // Treasury liquidityAsset balance

        // Pause protocol and attempt drawdown()
        assertTrue(globalAdmin.try_mapleGlobals_setProtocolPause(address(globals), true));
        assertTrue(!borrower1.try_loan_drawdown(address(loan), drawdownAmount));

        // Unpause protocol and drawdown()
        assertTrue(globalAdmin.try_mapleGlobals_setProtocolPause(address(globals), false));
        assertTrue(borrower1.try_loan_drawdown(address(loan), drawdownAmount));

        assertEq(IERC20(WETH).balanceOf(address(borrower1)),                                 0);  // Borrower collateral balance
        assertEq(IERC20(WETH).balanceOf(loan.collateralLocker()), reqCollateral);  // CollateralLocker collateral balance

        uint256 investorFee = drawdownAmount * globals.investorFee() / 10_000;
        uint256 treasuryFee = drawdownAmount * globals.treasuryFee() / 10_000;

        assertEq(IERC20(USDC).balanceOf(fundingLocker),                                         0);  // FundingLocker liquidityAsset balance
        assertEq(IERC20(USDC).balanceOf(address(loan)), fundAmount - drawdownAmount + investorFee);  // Loan liquidityAsset balance
        assertEq(loan.principalOwed(),                                     drawdownAmount);  // Principal owed
        assertEq(uint256(loan.loanState()),                                             1);  // Loan state: Active

        assertWithinDiff(IERC20(USDC).balanceOf(address(borrower1)), drawdownAmount - (investorFee + treasuryFee), 1); // Borrower liquidityAsset balance

        assertEq(loan.nextPaymentDue(), block.timestamp + loan.paymentIntervalSeconds());  // Next payment due timestamp calculated from time of drawdown

        // Fee related variables post-check.
        assertEq(loan.feePaid(),                                    investorFee);  // Drawdown amount
        assertEq(loan.excessReturned(),             fundAmount - drawdownAmount);  // Principal owed
        assertEq(IERC20(USDC).balanceOf(address(treasury)),                 treasuryFee);  // Treasury loanAsset balance

        // Test FDT accounting
        address debtLocker = pool1.debtLockers(address(loan), address(debtLockerFactory));
        assertEq(loan.balanceOf(debtLocker), fundAmount * WAD_SCALE / USDC_SCALE);
        assertWithinDiff(loan.withdrawableFundsOf(debtLocker), fundAmount - drawdownAmount + investorFee, 1);

        // Can't drawdown() loan after it has already been called.
        assertTrue(!borrower1.try_loan_drawdown(address(loan), drawdownAmount));
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
        fundAmount = IERC20(USDC).balanceOf(loan.fundingLocker());

        drawdownAmount = constrictToRange(drawdownAmount, loan.requestAmount(), fundAmount);

        assertEq(uint256(loan.loanState()), 0);  // Loan state: Ready

        assertTrue(!borrower1.try_loan_makePayment(address(loan)));  // Can't makePayment when State != Active

        // Approve collateral and drawdown loan.
        uint256 reqCollateral = drawdown(loan, drawdownAmount);
        uint256 loanPreBal    = IERC20(USDC).balanceOf(address(loan));  // Accounts for excess and fees from drawdown

        // NOTE: Do not need to hevm.warp in this test because payments can be made whenever as long as they are before the nextPaymentDue

        uint256 numPayments = loan.paymentsRemaining();
        // Approve 1st of 3 payments.
        (uint256 total, uint256 principal, uint256 interest, uint256 due, ) = loan.getNextPayment();
        if (total == 0 && interest == 0) return;  // If fuzz params cause payments to be so small they round to zero, skip fuzz iteration

        assertTrue(!borrower1.try_loan_makePayment(address(loan)));  // Can't makePayment with lack of approval

        erc20_mint(USDC, USDC_SLOT, address(borrower1), total);
        borrower1.erc20_approve(USDC, address(loan), total);

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
        assertTrue(!borrower1.try_loan_makePayment(address(loan)));

        // Unpause protocol and makePayment()
        assertTrue(globalAdmin.try_mapleGlobals_setProtocolPause(address(globals), false));
        assertTrue(borrower1.try_loan_makePayment(address(loan)));  // Make payment.

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
        (total, principal, interest, due, ) = loan.getNextPayment();
        erc20_mint(USDC, USDC_SLOT, address(borrower1), total);
        borrower1.erc20_approve(USDC, address(loan), total);

        // Check CollateralLocker balance.
        assertEq(IERC20(WETH).balanceOf(loan.collateralLocker()), reqCollateral);

        // Make last payment.
        assertTrue(borrower1.try_loan_makePayment(address(loan)));

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
        assertEq(IERC20(WETH).balanceOf(loan.collateralLocker()),            0);
        assertEq(IERC20(WETH).balanceOf(address(borrower1)),            reqCollateral);
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
        fundAmount = IERC20(USDC).balanceOf(fundingLocker);

        drawdownAmount = constrictToRange(drawdownAmount, loan.requestAmount(), fundAmount);

        assertEq(uint256(loan.loanState()), 0);  // Loan state: Ready

        assertTrue(!borrower1.try_loan_makePayment(address(loan)));  // Can't makePayment when State != Active

        // Approve collateral and drawdown loan.
        uint256 reqCollateral = drawdown(loan, drawdownAmount);
        uint256 loanPreBal    = IERC20(USDC).balanceOf(address(loan));  // Accounts for excess and fees from drawdown
        uint256 numPayments   = loan.paymentsRemaining();

        // Approve 1st of 3 payments.
        (uint256 total, uint256 principal, uint256 interest, uint256 due, ) = loan.getNextPayment();
        if (total == 0 && interest == 0) return;  // If fuzz params cause payments to be so small they round to zero, skip fuzz iteration

        assertTrue(!borrower1.try_loan_makePayment(address(loan)));  // Can't makePayment with lack of approval

        erc20_mint(USDC, USDC_SLOT, address(borrower1), total);
        borrower1.erc20_approve(USDC, address(loan), total);

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
        assertTrue(borrower1.try_loan_makePayment(address(loan)));

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
        (total, principal, interest_late, due, ) = loan.getNextPayment();
        erc20_mint(USDC, USDC_SLOT, address(borrower1), total);
        borrower1.erc20_approve(USDC, address(loan), total);

        // Check CollateralLocker balance.
        assertEq(IERC20(WETH).balanceOf(loan.collateralLocker()), reqCollateral);

        // Make payment.
        assertTrue(borrower1.try_loan_makePayment(address(loan)));

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
        assertEq(IERC20(WETH).balanceOf(loan.collateralLocker()),             0);
        assertEq(IERC20(WETH).balanceOf(address(borrower1)),            reqCollateral);
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
        fundAmount = IERC20(USDC).balanceOf(fundingLocker);

        // Warp to the fundingPeriod, can't call unwind() yet
        hevm.warp(loan.createdAt() + globals.fundingPeriod());
        assertTrue(!LoanUser(address(poolDelegate1)).try_loan_unwind(address(loan)));

        uint256 flBalancePre   = IERC20(USDC).balanceOf(fundingLocker);
        uint256 loanBalancePre = IERC20(USDC).balanceOf(address(loan));
        uint256 loanStatePre   = uint256(loan.loanState());

        assertEq(flBalancePre, fundAmount);
        assertEq(loanStatePre, 0);

        // Warp 1 more second, can call unwind()
        hevm.warp(loan.createdAt() + globals.fundingPeriod() + 1);

        // Pause protocol and attempt unwind()
        assertTrue(globalAdmin.try_mapleGlobals_setProtocolPause(address(globals), true));
        assertTrue(!LoanUser(address(poolDelegate1)).try_loan_unwind(address(loan)));

        // Unpause protocol and unwind()
        assertTrue(globalAdmin.try_mapleGlobals_setProtocolPause(address(globals), false));
        assertTrue(LoanUser(address(poolDelegate1)).try_loan_unwind(address(loan)));

        uint256 flBalancePost   = IERC20(USDC).balanceOf(fundingLocker);
        uint256 loanBalancePost = IERC20(USDC).balanceOf(address(loan));
        uint256 loanStatePost   = uint256(loan.loanState());

        assertEq(flBalancePost, 0);
        assertEq(loanStatePost, 3);

        assertEq(flBalancePre,    fundAmount);
        assertEq(loanBalancePost, fundAmount);

        assertEq(loan.excessReturned(), loanBalancePost);

        // Pause protocol and attempt withdrawFunds() (through claim)
        assertTrue(globalAdmin.try_mapleGlobals_setProtocolPause(address(globals), true));
        assertTrue(!poolDelegate1.try_pool_claim(address(pool1), address(loan), address(debtLockerFactory)));

        // Unpause protocol and withdrawFunds() (through claim)
        assertTrue(globalAdmin.try_mapleGlobals_setProtocolPause(address(globals), false));
        assertTrue(poolDelegate1.try_pool_claim(address(pool1), address(loan), address(debtLockerFactory)));

        assertWithinDiff(IERC20(USDC).balanceOf(pool1.liquidityLocker()), fundAmount, 1);
        assertWithinDiff(IERC20(USDC).balanceOf(address(loan)),                            0, 1);

        // Can't unwind() loan after it has already been called.
        assertTrue(!LoanUser(address(poolDelegate1)).try_loan_unwind(address(loan)));
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
        governor.mapleGlobals_setMaxSwapSlippage(address(globals), 10_000);  // Set 100% slippage to account for very large liquidations from fuzzing

        loan = instantiateAndFundLoan(apr, index, numPayments_, requestAmount, collateralRatio, fundAmount);
        address fundingLocker = loan.fundingLocker();
        fundAmount = IERC20(USDC).balanceOf(fundingLocker);
        uint256 wadAmount = fundAmount * WAD_SCALE / USDC_SCALE;

        drawdownAmount = constrictToRange(drawdownAmount, loan.requestAmount(), fundAmount);

        address debtLocker = pool1.debtLockers(address(loan), address(debtLockerFactory));

        assertEq(uint256(loan.loanState()), 0);  // `Ready` state

        uint256 reqCollateral = drawdown(loan, drawdownAmount);

        assertEq(uint256(loan.loanState()), 1);  // `Active` state

        assertTrue(!poolDelegate1.try_pool_triggerDefault(address(pool1), address(loan), address(debtLockerFactory)));  // Should fail to trigger default because current time is still less than the `nextPaymentDue`.
        assertTrue( !explorer.try_loan_triggerDefault(address(loan)));                                    // Failed because commoner in not allowed to default the loan because they do not own any LoanFDTs.

        hevm.warp(loan.nextPaymentDue() + 1);

        assertTrue(!poolDelegate1.try_pool_triggerDefault(address(pool1), address(loan), address(debtLockerFactory)));  // Failed because still loan has defaultGracePeriod to repay the dues.
        assertTrue( !explorer.try_loan_triggerDefault(address(loan)));                                    // Failed because still commoner is not allowed to default the loan.

        hevm.warp(loan.nextPaymentDue() + globals.defaultGracePeriod());

        assertTrue(!poolDelegate1.try_pool_triggerDefault(address(pool1), address(loan), address(debtLockerFactory)));  // Failed because still loan has defaultGracePeriod to repay the dues.
        assertTrue( !explorer.try_loan_triggerDefault(address(loan)));                                   // Failed because still commoner is not allowed to default the loan.

        hevm.warp(loan.nextPaymentDue() + globals.defaultGracePeriod() + 1);

        assertTrue(!explorer.try_loan_triggerDefault(address(loan)));                                   // Failed because still commoner is not allowed to default the loan.

        // Sid's Pool currently has 100% of LoanFDTs, so he can trigger the loan default.
        // For this test, minLoanEquity is transferred to the commoner to test the minimum loan equity condition.
        assertEq(loan.totalSupply(), wadAmount);
        assertEq(globals.minLoanEquity(),             2000);  // 20%

        uint256 minEquity = loan.totalSupply() * globals.minLoanEquity() / 10_000;

        // Simulate transfer of LoanFDTs from DebtLocker to commoner (<20% of total supply)
        hevm.store(
            address(loan),
            keccak256(abi.encode(address(explorer), 0)), // Mint tokens
            bytes32(uint256(minEquity - 1))
        );

        hevm.store(
            address(loan),
            keccak256(abi.encode(debtLocker, 0)), // Overwrite balance
            bytes32(uint256(wadAmount - minEquity + 1))
        );

        assertTrue(!explorer.try_loan_triggerDefault(address(loan)));  // Failed because still commoner is not allowed to default the loan.

        // "Transfer" 1 more wei to meet 20% minimum equity requirement
        hevm.store(
            address(loan),
            keccak256(abi.encode(address(explorer), 0)), // Mint tokens
            bytes32(uint256(minEquity))
        );

        hevm.store(
            address(loan),
            keccak256(abi.encode(debtLocker, 0)), // Overwrite balance
            bytes32(uint256(wadAmount - minEquity))
        );

        assertTrue(explorer.try_loan_triggerDefault(address(loan)));  // Now with 20% of loan equity, a loan can be defaulted
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

        drawdownAmount = constrictToRange(drawdownAmount, loan.requestAmount(), fundAmount);

        uint256 reqCollateral = drawdown(loan, drawdownAmount);

        uint256 expectedAmount = (reqCollateral * globals.getLatestPrice(WETH)) / globals.getLatestPrice(USDC);

        assertEq((expectedAmount * USDC_SCALE) / WAD_SCALE, loan.getExpectedAmountRecovered());
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
        fundAmount = IERC20(USDC).balanceOf(loan.fundingLocker());

        drawdownAmount = constrictToRange(drawdownAmount, loan.requestAmount(), fundAmount);

        assertEq(uint256(loan.loanState()), 0);  // Loan state: Ready

        assertTrue(!borrower1.try_loan_makeFullPayment(address(loan)));  // Can't makePayment when State != Active

        // Approve collateral and drawdown loan.
        uint256 reqCollateral = drawdown(loan, drawdownAmount);
        uint256 loanPreBal    = IERC20(USDC).balanceOf(address(loan));

        assertTrue(!borrower1.try_loan_makeFullPayment(address(loan)));  // Can't makePayment with lack of approval

        // Approve full payment.
        (uint256 total, uint256 principal, uint256 interest) = loan.getFullPayment();
        erc20_mint(USDC, USDC_SLOT, address(borrower1), total);
        borrower1.erc20_approve(USDC, address(loan), total);

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
        assertEq(IERC20(WETH).balanceOf(loan.collateralLocker()), reqCollateral);
        assertEq(IERC20(WETH).balanceOf(address(borrower1)),                 0);

        // Pause protocol and attempt makeFullPayment()
        assertTrue(globalAdmin.try_mapleGlobals_setProtocolPause(address(globals), true));
        assertTrue(!borrower1.try_loan_makeFullPayment(address(loan)));

        // Unpause protocol and makeFullPayment()
        assertTrue(globalAdmin.try_mapleGlobals_setProtocolPause(address(globals), false));
        assertTrue(borrower1.try_loan_makeFullPayment(address(loan)));  // Make full payment.

        // After state
        assertEq(IERC20(USDC).balanceOf(address(loan)), loanPreBal + total);

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
        assertEq(IERC20(WETH).balanceOf(loan.collateralLocker()),             0);
        assertEq(IERC20(WETH).balanceOf(address(borrower1)),     reqCollateral);
    }

    function test_reclaim_erc20() external {
        loan = instantiateAndFundLoan(2, 10, 5, 100000, 20, 1000000);
        // Add different kinds of assets to the loan.
        erc20_mint(USDC, USDC_SLOT, address(loan), 1000 * USDC_SCALE);
        erc20_mint(DAI,  DAI_SLOT,  address(loan), 1000 * WAD_SCALE);
        erc20_mint(WETH, WETH_SLOT, address(loan),  100 * WAD_SCALE);

        Governor fakeGov = new Governor();

        uint256 beforeBalanceDAI  = IERC20(DAI).balanceOf(address(governor));
        uint256 beforeBalanceWETH = IERC20(WETH).balanceOf(address(governor));

        assertTrue(!fakeGov.try_loan_reclaimERC20(address(loan), DAI));
        assertTrue(    !governor.try_loan_reclaimERC20(address(loan), USDC));  // Governor cannot remove liquidityAsset from loans
        assertTrue(    !governor.try_loan_reclaimERC20(address(loan), address(0)));
        assertTrue(     governor.try_loan_reclaimERC20(address(loan), WETH));
        assertTrue(     governor.try_loan_reclaimERC20(address(loan), DAI));

        uint256 afterBalanceDAI  = IERC20(DAI).balanceOf(address(governor));
        uint256 afterBalanceWETH = IERC20(WETH).balanceOf(address(governor));

        assertEq(afterBalanceDAI  - beforeBalanceDAI,  1000 * WAD_SCALE);
        assertEq(afterBalanceWETH - beforeBalanceWETH,  100 * WAD_SCALE);
    }

    function test_setLoanAdmin() public {
        GlobalAdmin newLoanAdmin = new GlobalAdmin();
        loan = instantiateAndFundLoan(2, 10, 5, 100000, 20, 1000000);

        // Pause protocol and attempt setLoanAdmin()
        assertTrue(globalAdmin.try_mapleGlobals_setProtocolPause(address(globals), true));
        assertTrue(!borrower1.try_loan_setLoanAdmin(address(loan), address(newLoanAdmin), true));
        assertTrue(!loan.loanAdmins(address(newLoanAdmin)));

        // Unpause protocol and setLoanAdmin()
        assertTrue(globalAdmin.try_mapleGlobals_setProtocolPause(address(globals), false));
        assertTrue(borrower1.try_loan_setLoanAdmin(address(loan), address(newLoanAdmin), true));
        assertTrue(loan.loanAdmins(address(newLoanAdmin)));
    }

    function repetitivePayment(ILoan loan_, uint256 numPayments, uint256 paymentCount, uint256 drawdownAmount, uint256 loanPreBal, uint256 oldInterest) internal {
        (uint256 total,, uint256 interest, uint256 due, ) = loan_.getNextPayment();
        erc20_mint(USDC, USDC_SLOT, address(borrower1), total);
        borrower1.erc20_approve(USDC, address(loan_), total);

        // Below is the way of catering two scenarios
        // 1. When there is no late payment so interest paid will be a multiple of `numPayments`.
        // 2. If there is a late payment then needs to handle the situation where interest paid is `interest (without late fee) + interest (late fee) * numPayments`.
        numPayments = oldInterest == uint256(0) ? numPayments - paymentCount : numPayments - paymentCount - 1;

        // Make payment.
        assertTrue(borrower1.try_loan_makePayment(address(loan_)));

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
