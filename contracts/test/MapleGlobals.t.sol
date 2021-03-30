// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "./user/Governor.sol";
import "./user/PoolDelegate.sol";

import "../RepaymentCalc.sol";
import "../CollateralLockerFactory.sol";
import "../DebtLockerFactory.sol";
import "../FundingLockerFactory.sol";
import "../LateFeeCalc.sol";
import "../LiquidityLockerFactory.sol";
import "../LoanFactory.sol";
import "../MapleTreasury.sol";
import "../PoolFactory.sol";
import "../PremiumCalc.sol";
import "../StakeLockerFactory.sol";

import "../oracles/ChainlinkOracle.sol";
import "../oracles/UsdOracle.sol";

import "module/maple-token/contracts/MapleToken.sol";

import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract MapleGlobalsTest is TestUtil {

    Governor                         gov;
    PoolDelegate                     sid;
    PoolDelegate                     joe;

    RepaymentCalc          repaymentCalc;
    CollateralLockerFactory    clFactory;
    DebtLockerFactory          dlFactory;
    FundingLockerFactory       flFactory;
    LateFeeCalc                   lfCalc;
    LiquidityLockerFactory     llFactory;
    LoanFactory              loanFactory;
    MapleGlobals                 globals;
    MapleToken                       mpl;
    MapleTreasury                    trs;
    PoolFactory              poolFactory;
    PremiumCalc                    pCalc;
    StakeLockerFactory         slFactory;
    ChainlinkOracle           wethOracle;
    ChainlinkOracle           wbtcOracle;
    UsdOracle                  usdOracle;

    ERC20                     fundsToken;

    uint8 public constant CL_FACTORY = 0;           // Factory type of `CollateralLockerFactory`.
    uint8 public constant DL_FACTORY = 1;           // Factory type of `DebtLockerFactory`.
    uint8 public constant FL_FACTORY = 2;           // Factory type of `FundingLockerFactory`.
    uint8 public constant LL_FACTORY = 3;           // Factory type of `LiquidityLockerFactory`.
    uint8 public constant SL_FACTORY = 4;           // Factory type of `StakeLockerFactory`.

    uint8 public constant INTEREST_CALC_TYPE = 10;  // Calc type of `RepaymentCalc`.
    uint8 public constant LATEFEE_CALC_TYPE  = 11;  // Calc type of `LateFeeCalc`.
    uint8 public constant PREMIUM_CALC_TYPE  = 12;  // Calc type of `PremiumCalc`.

    function setUp() public {

        gov         = new Governor();       // Actor: Governor of Maple.
        sid         = new PoolDelegate();   // Actor: Manager of the Pool.
        joe         = new PoolDelegate();   // Actor: Manager of the Pool.

        mpl           = new MapleToken("MapleToken", "MAPLE", USDC);
        globals       = gov.createGlobals(address(mpl), BPOOL_FACTORY);
        poolFactory   = new PoolFactory(address(globals));
        loanFactory   = new LoanFactory(address(globals));
        dlFactory     = new DebtLockerFactory();
        slFactory     = new StakeLockerFactory();
        llFactory     = new LiquidityLockerFactory();
        flFactory     = new FundingLockerFactory();
        clFactory     = new CollateralLockerFactory();
        lfCalc        = new LateFeeCalc(0);
        pCalc         = new PremiumCalc(200);
        repaymentCalc = new RepaymentCalc();
        trs           = new MapleTreasury(address(mpl), USDC, UNISWAP_V2_ROUTER_02, address(globals)); 
        wethOracle    = new ChainlinkOracle(tokens["WETH"].orcl, WETH, address(this));
        wbtcOracle    = new ChainlinkOracle(tokens["WBTC"].orcl, WBTC, address(this));
        usdOracle     = new UsdOracle();
        
        gov.setPriceOracle(WETH, address(wethOracle));
        gov.setPriceOracle(WBTC, address(wbtcOracle));
        gov.setPriceOracle(USDC, address(usdOracle));

        // The following code was adopted from maple-core/scripts/setup.js
        gov.setMapleTreasury(address(trs));
        gov.setPoolDelegateAllowlist(address(sid), true);

        gov.setLoanAsset(DAI,        true);
        gov.setLoanAsset(USDC,       true);
        gov.setCollateralAsset(DAI,  true);
        gov.setCollateralAsset(USDC, true);
        gov.setCollateralAsset(WETH, true);
        gov.setCollateralAsset(WBTC, true);

        gov.setCalc(address(lfCalc),        true);
        gov.setCalc(address(pCalc),         true);
        gov.setCalc(address(repaymentCalc), true);

        gov.setValidPoolFactory(address(poolFactory), true);
        gov.setValidLoanFactory(address(loanFactory), true);

        gov.setValidSubFactory(address(poolFactory), address(slFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(llFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(dlFactory), true);
        gov.setValidSubFactory(address(loanFactory), address(clFactory), true);
        gov.setValidSubFactory(address(loanFactory), address(flFactory), true);
    }

    function test_constructor() public {

        globals = new MapleGlobals(address(gov), address(mpl), BPOOL_FACTORY, address(1));

        assertEq(globals.governor(),         address(gov));
        assertEq(globals.mpl(),              address(mpl));
        assertEq(globals.gracePeriod(),            5 days);
        assertEq(globals.swapOutRequired(),        10_000);
        assertEq(globals.unstakeDelay(),          90 days);
        assertEq(globals.drawdownGracePeriod(),   10 days);
        assertEq(globals.investorFee(),                50);
        assertEq(globals.treasuryFee(),                50);
        assertEq(globals.BFactory(),        BPOOL_FACTORY);
        assertEq(globals.maxSwapSlippage(),          1000);
        assertEq(globals.minLoanEquity(),            2000);
        assertEq(globals.admin(),              address(1));
    }

    function test_setup() public {
        assertTrue(globals.isValidPoolDelegate(address(sid)));

        assertTrue(globals.isValidLoanAsset(DAI));
        assertTrue(globals.isValidLoanAsset(USDC));

        assertTrue(globals.isValidCollateralAsset(DAI));
        assertTrue(globals.isValidCollateralAsset(USDC));
        assertTrue(globals.isValidCollateralAsset(WETH));
        assertTrue(globals.isValidCollateralAsset(WBTC));

        assertTrue(globals.validCalcs(address(lfCalc)));
        assertTrue(globals.validCalcs(address(pCalc)));
        assertTrue(globals.validCalcs(address(repaymentCalc)));

        assertTrue(globals.isValidCalc(address(lfCalc),         LATEFEE_CALC_TYPE));
        assertTrue(globals.isValidCalc(address(pCalc),          PREMIUM_CALC_TYPE));
        assertTrue(globals.isValidCalc(address(repaymentCalc), INTEREST_CALC_TYPE));

        assertTrue(globals.isValidPoolFactory(address(poolFactory)));
        assertTrue(globals.isValidLoanFactory(address(loanFactory)));

        assertTrue(globals.validSubFactories(address(poolFactory), address(slFactory)));
        assertTrue(globals.validSubFactories(address(poolFactory), address(llFactory)));
        assertTrue(globals.validSubFactories(address(poolFactory), address(dlFactory)));
        assertTrue(globals.validSubFactories(address(loanFactory), address(clFactory)));
        assertTrue(globals.validSubFactories(address(loanFactory), address(flFactory)));
        
        assertTrue(globals.isValidSubFactory(address(poolFactory), address(slFactory), SL_FACTORY));
        assertTrue(globals.isValidSubFactory(address(poolFactory), address(llFactory), LL_FACTORY));
        assertTrue(globals.isValidSubFactory(address(poolFactory), address(dlFactory), DL_FACTORY));
        assertTrue(globals.isValidSubFactory(address(loanFactory), address(clFactory), CL_FACTORY));
        assertTrue(globals.isValidSubFactory(address(loanFactory), address(flFactory), FL_FACTORY));
    }

    function test_setters() public {

        Governor fakeGov  = new Governor();
        Governor fakeGov2 = new Governor();
        fakeGov.setGovGlobals(globals);  // Point to globals created by gov.
        fakeGov2.setGovGlobals(globals);

        // setValidPoolFactory()
        assertTrue(!globals.isValidPoolFactory(address(sid)));             // Use dummy address since poolFactory is already valid
        assertTrue(!fakeGov.try_setValidPoolFactory(address(sid), true));  // Non-governor cant set
        assertTrue(     gov.try_setValidPoolFactory(address(sid), true));
        assertTrue( globals.isValidPoolFactory(address(sid)));
        assertTrue(     gov.try_setValidPoolFactory(address(sid), false));
        assertTrue(!globals.isValidPoolFactory(address(sid)));

        // setValidLoanFactory()
        assertTrue(!globals.isValidLoanFactory(address(sid)));             // Use dummy address since loanFactory is already valid
        assertTrue(!fakeGov.try_setValidLoanFactory(address(sid), true));  // Non-governor cant set
        assertTrue(     gov.try_setValidLoanFactory(address(sid), true));
        assertTrue( globals.isValidLoanFactory(address(sid)));
        assertTrue(     gov.try_setValidLoanFactory(address(sid), false));
        assertTrue(!globals.isValidLoanFactory(address(sid)));

        // setValidSubFactory()
        assertTrue( globals.validSubFactories(address(poolFactory), address(dlFactory)));
        assertTrue(!fakeGov.try_setValidSubFactory(address(poolFactory), address(dlFactory), false));  // Non-governor cant set
        assertTrue(     gov.try_setValidSubFactory(address(poolFactory), address(dlFactory), false));
        assertTrue(!globals.validSubFactories(address(poolFactory), address(dlFactory)));
        assertTrue(     gov.try_setValidSubFactory(address(poolFactory), address(dlFactory), true));
        assertTrue( globals.validSubFactories(address(poolFactory), address(dlFactory)));
        
        // setPoolDelegateAllowlist()
        assertTrue(!globals.isValidPoolDelegate(address(joe)));
        assertTrue(!fakeGov.try_setPoolDelegateAllowlist(address(joe), true));  // Non-governor cant set
        assertTrue(     gov.try_setPoolDelegateAllowlist(address(joe), true));
        assertTrue( globals.isValidPoolDelegate(address(joe)));
        assertTrue(     gov.try_setPoolDelegateAllowlist(address(joe), false));
        assertTrue(!globals.isValidPoolDelegate(address(joe)));

        // setDefaultUniswapPath()
        assertTrue(!fakeGov.try_setDefaultUniswapPath(WETH, USDC, USDC));  // Non-governor cant set
        assertEq(   globals.defaultUniswapPath(WETH, USDC), address(0));
        assertEq(   globals.defaultUniswapPath(WBTC, USDC), address(0));
        assertTrue(     gov.try_setDefaultUniswapPath(WETH, USDC, USDC));
        assertTrue(     gov.try_setDefaultUniswapPath(WBTC, USDC, WETH));
        assertEq(   globals.defaultUniswapPath(WETH, USDC), USDC);
        assertEq(   globals.defaultUniswapPath(WBTC, USDC), WETH);

        // setLoanAsset() 
        assertTrue(!globals.isValidLoanAsset(WETH));
        assertTrue(!fakeGov.try_setLoanAsset(WETH,  true));  // Non-governor cant set
        assertTrue(     gov.try_setLoanAsset(WETH,  true));
        assertTrue(globals.isValidLoanAsset(WETH));
        assertTrue(!fakeGov.try_setLoanAsset(WETH,  false));  // Non-governor cant set
        assertTrue(     gov.try_setLoanAsset(WETH,  false));
        assertTrue(!globals.isValidLoanAsset(WETH));

        // setCollateralAsset()
        assertTrue(!globals.isValidCollateralAsset(CDAI));
        assertTrue(!fakeGov.try_setCollateralAsset(CDAI,   true));  // Non-governor cant set
        assertTrue(     gov.try_setCollateralAsset(CDAI,   true));
        assertTrue( globals.isValidCollateralAsset(CDAI));
        assertTrue(!fakeGov.try_setCollateralAsset(CDAI,   false));  // Non-governor cant set
        assertTrue(     gov.try_setCollateralAsset(CDAI,   false));
        assertTrue(!globals.isValidCollateralAsset(CDAI));

        // setCalc()
        assertTrue( globals.validCalcs(address(repaymentCalc)));
        assertTrue(!fakeGov.try_setCalc(address(repaymentCalc), false));  // Non-governor cant set
        assertTrue(     gov.try_setCalc(address(repaymentCalc), false));
        assertTrue(!globals.validCalcs(address(repaymentCalc)));

        // setInvestorFee()
        assertTrue(     gov.try_setInvestorFee(     0));  // Set to zero to test upper bound condition for treasuryFee
        assertTrue(     gov.try_setTreasuryFee(     0));  // Set to zero to test upper bound condition for investorFee

        assertEq(   globals.investorFee(),          0);
        assertTrue(!fakeGov.try_setInvestorFee(10_000));  // Non-governor cant set
        assertTrue(    !gov.try_setInvestorFee(10_001));  // 100.01% is outside of bounds
        assertTrue(     gov.try_setInvestorFee(10_000));  // 100% is upper bound
        assertEq(   globals.investorFee(),     10_000);
        assertTrue(     gov.try_setInvestorFee(     0));  // Set to zero to test combined condition

        // setTreasuryFee()
        assertEq(   globals.treasuryFee(),          0);
        assertTrue(!fakeGov.try_setTreasuryFee(10_000));  // Non-governor cant set
        assertTrue(    !gov.try_setTreasuryFee(10_001));  // 100.01% is outside of bounds
        assertTrue(     gov.try_setTreasuryFee(10_000));  // 100% is upper bound
        assertEq(   globals.treasuryFee(),     10_000);
        assertTrue(     gov.try_setTreasuryFee(     0));  // Set to zero to test combined condition

        // investorFee + treasuryFee <= 100%
        assertTrue(     gov.try_setInvestorFee(5_000));  // 100% is combined upper bound
        assertTrue(     gov.try_setTreasuryFee(5_000));  // 100% is combined upper bound
        assertTrue(    !gov.try_setInvestorFee(5_001));  // 100% is combined upper bound
        assertTrue(    !gov.try_setTreasuryFee(5_001));  // 100% is combined upper bound

        // setDrawdownGracePeriod()
        assertEq(   globals.drawdownGracePeriod(),    10 days);
        assertTrue(!fakeGov.try_setDrawdownGracePeriod(1 days));
        assertTrue(    !gov.try_setDrawdownGracePeriod(1 days - 1));  // Lower bound is 1 day
        assertTrue(     gov.try_setDrawdownGracePeriod(1 days));
        assertEq(   globals.drawdownGracePeriod(),     1 days);

        // setGracePeriod()
        assertEq(   globals.gracePeriod(),     5 days);
        assertTrue(!fakeGov.try_setGracePeriod(1 days));
        assertTrue(    !gov.try_setGracePeriod(1 days - 1));   // Lower bound is 1 day
        assertTrue(     gov.try_setGracePeriod(1 days));
        assertEq(   globals.gracePeriod(),     1 days);

        // setSwapOutRequired()
        assertEq(   globals.swapOutRequired(),     10_000);
        assertTrue(!fakeGov.try_setSwapOutRequired(15_000));
        assertTrue(    !gov.try_setSwapOutRequired( 9_999));  // Lower bound is $10,000 of pool cover
        assertTrue(     gov.try_setSwapOutRequired(15_000));
        assertEq(   globals.swapOutRequired(),     15_000);
        assertTrue(     gov.try_setSwapOutRequired(10_000));  // Lower bound is $10,000 of pool cover
        assertEq(   globals.swapOutRequired(),     10_000);

        // setUnstakeDelay()
        assertEq(   globals.unstakeDelay(),    90 days);
        assertTrue(!fakeGov.try_setUnstakeDelay(1 days));
        assertTrue(    !gov.try_setUnstakeDelay(1 days - 1));
        assertTrue(     gov.try_setUnstakeDelay(1 days));
        assertEq(   globals.unstakeDelay(),     1 days);

         // setMapleTreasury()
        assertEq(   globals.mapleTreasury(), address(trs));
        assertTrue(!fakeGov.try_setMapleTreasury(address(this)));
        assertTrue(    !gov.try_setMapleTreasury(address(0)));
        assertTrue(     gov.try_setMapleTreasury(address(this)));
        assertEq(   globals.mapleTreasury(), address(this)); 

        // setPriceOracle()
        assertTrue(!fakeGov.try_setPriceOracle(WETH, address(1)));
        assertTrue(     gov.try_setPriceOracle(WETH, address(wethOracle)));
        assertTrue(     gov.try_setPriceOracle(WBTC, address(wbtcOracle)));
        assertEq(globals.oracleFor(WETH),            address(wethOracle));
        assertEq(globals.oracleFor(WBTC),            address(wbtcOracle));

        assertTrue(globals.getLatestPrice(WETH) != 0); // Shows real WETH value from Chainlink
        assertTrue(globals.getLatestPrice(WBTC) != 0); // Shows real WBTC value from Chainlink

        // setMaxSwapSlippage()
        assertEq(   globals.maxSwapSlippage(),      1_000);
        assertTrue(!fakeGov.try_setMaxSwapSlippage(10_000));
        assertTrue(    !gov.try_setMaxSwapSlippage(10_001));  // 100.01% is outside of bounds
        assertTrue(     gov.try_setMaxSwapSlippage(10_000));  // 100% is upper bound
        assertEq(   globals.maxSwapSlippage(),     10_000);

        // setValidMplRewards()
        assertTrue(!globals.isValidMplRewards(address(1)));
        assertTrue(!fakeGov.try_setValidMplRewards(address(1), true));
        assertTrue(     gov.try_setValidMplRewards(address(1), true));
        assertTrue( globals.isValidMplRewards(address(1))); 

        // setValidBalancerPool()
        assertTrue(!globals.isValidBalancerPool(address(1)));
        assertTrue(!fakeGov.try_setValidBalancerPool(address(1), true));
        assertTrue(     gov.try_setValidBalancerPool(address(1), true));
        assertTrue( globals.isValidBalancerPool(address(1))); 

        // setMinLoanEquity
        assertEq(   globals.minLoanEquity(),      2_000);
        assertTrue(!fakeGov.try_setMinLoanEquity(10_000)); 
        assertTrue(    !gov.try_setMinLoanEquity(10_001));  // 100.01% is outside of bounds
        assertTrue(     gov.try_setMinLoanEquity(10_000));  // 99.99 %
        assertEq(   globals.minLoanEquity(),     10_000);   // 100% is upper bound
    }

    function test_transfer_governor() public {
        Governor fakeGov  = new Governor();
        Governor fakeGov2 = new Governor();
        fakeGov.setGovGlobals(globals);  // Point to globals created by gov.
        fakeGov2.setGovGlobals(globals);
        
        // Transfer Governor
        assertTrue( !fakeGov.try_setPendingGovernor(address(fakeGov)));
        assertTrue(     !gov.try_setPendingGovernor(address(0)));       // Cannot set governor to zero
        assertTrue(      gov.try_setPendingGovernor(address(fakeGov2)));
        assertTrue(      gov.try_setPendingGovernor(address(fakeGov)));
        assertEq(    globals.pendingGovernor(), address(fakeGov));
        assertEq(    globals.governor(), address(gov));
        assertTrue( !fakeGov.try_setPendingGovernor(address(fakeGov2)));  // Trying to assign the permission to someone else.
        assertTrue(!fakeGov2.try_acceptGovernor());
        assertTrue(  fakeGov.try_acceptGovernor());
        assertEq(    globals.governor(), address(fakeGov));
    }
}
