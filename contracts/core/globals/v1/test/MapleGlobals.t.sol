// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import { TestUtil } from "../../../../test/TestUtil.sol";
import { Governor } from "../../../../test/user/Governor.sol";

import { MapleGlobals } from "../MapleGlobals.sol";

contract MapleGlobalsTest is TestUtil {

    function setUp() public {
        setUpGlobals();
        setUpTokens();
        setUpOracles();
        setUpFactories();
        setUpCalcs();
        setUpPoolDelegates();
    }

    function test_constructor() public {

        globals = new MapleGlobals(address(gov), address(mpl), address(1));

        assertEq(globals.governor(),         address(gov));
        assertEq(globals.mpl(),              address(mpl));
        assertEq(globals.defaultGracePeriod(),     5 days);
        assertEq(globals.swapOutRequired(),        10_000);
        assertEq(globals.fundingPeriod(),         10 days);
        assertEq(globals.investorFee(),                50);
        assertEq(globals.treasuryFee(),                50);
        assertEq(globals.maxSwapSlippage(),          1000);
        assertEq(globals.minLoanEquity(),            2000);
        assertEq(globals.globalAdmin(),        address(1));
    }

    function test_setup() public {
        assertTrue(globals.isValidPoolDelegate(address(pat)));

        assertTrue(globals.isValidLiquidityAsset(DAI));
        assertTrue(globals.isValidLiquidityAsset(USDC));

        assertTrue(globals.isValidCollateralAsset(DAI));
        assertTrue(globals.isValidCollateralAsset(USDC));
        assertTrue(globals.isValidCollateralAsset(WETH));
        assertTrue(globals.isValidCollateralAsset(WBTC));

        assertTrue(globals.validCalcs(address(lateFeeCalc)));
        assertTrue(globals.validCalcs(address(premiumCalc)));
        assertTrue(globals.validCalcs(address(repaymentCalc)));

        assertTrue(globals.isValidCalc(address(lateFeeCalc),   LATEFEE_CALC_TYPE));
        assertTrue(globals.isValidCalc(address(premiumCalc),   PREMIUM_CALC_TYPE));
        assertTrue(globals.isValidCalc(address(repaymentCalc), INTEREST_CALC_TYPE));

        assertTrue(globals.isValidPoolFactory(address(poolFactory)));
        assertTrue(globals.isValidLoanFactory(address(loanFactory)));

        assertTrue(globals.validSubFactories(address(poolFactory), address(slFactory)));
        assertTrue(globals.validSubFactories(address(poolFactory), address(llFactory)));
        assertTrue(globals.validSubFactories(address(poolFactory), address(dlFactory1)));
        assertTrue(globals.validSubFactories(address(loanFactory), address(clFactory)));
        assertTrue(globals.validSubFactories(address(loanFactory), address(flFactory)));

        assertTrue(globals.isValidSubFactory(address(poolFactory), address(slFactory),  SL_FACTORY));
        assertTrue(globals.isValidSubFactory(address(poolFactory), address(llFactory),  LL_FACTORY));
        assertTrue(globals.isValidSubFactory(address(poolFactory), address(dlFactory1), DL_FACTORY));
        assertTrue(globals.isValidSubFactory(address(loanFactory), address(clFactory),  CL_FACTORY));
        assertTrue(globals.isValidSubFactory(address(loanFactory), address(flFactory),  FL_FACTORY));
    }

    function test_setters() public {

        Governor fakeGov  = new Governor();
        Governor fakeGov2 = new Governor();
        fakeGov.setGovGlobals(globals);  // Point to globals created by gov.
        fakeGov2.setGovGlobals(globals);

        // setValidPoolFactory()
        assertTrue(!globals.isValidPoolFactory(address(pat)));             // Use dummy address since poolFactory is already valid
        assertTrue(!fakeGov.try_setValidPoolFactory(address(pat), true));  // Non-governor cant set
        assertTrue(     gov.try_setValidPoolFactory(address(pat), true));
        assertTrue( globals.isValidPoolFactory(address(pat)));
        assertTrue(     gov.try_setValidPoolFactory(address(pat), false));
        assertTrue(!globals.isValidPoolFactory(address(pat)));

        // setValidLoanFactory()
        assertTrue(!globals.isValidLoanFactory(address(pat)));             // Use dummy address since loanFactory is already valid
        assertTrue(!fakeGov.try_setValidLoanFactory(address(pat), true));  // Non-governor cant set
        assertTrue(     gov.try_setValidLoanFactory(address(pat), true));
        assertTrue( globals.isValidLoanFactory(address(pat)));
        assertTrue(     gov.try_setValidLoanFactory(address(pat), false));
        assertTrue(!globals.isValidLoanFactory(address(pat)));

        // setValidSubFactory()
        assertTrue( globals.validSubFactories(address(poolFactory), address(dlFactory1)));
        assertTrue(!fakeGov.try_setValidSubFactory(address(poolFactory), address(dlFactory1), false));  // Non-governor cant set
        assertTrue(     gov.try_setValidSubFactory(address(poolFactory), address(dlFactory1), false));
        assertTrue(!globals.validSubFactories(address(poolFactory), address(dlFactory1)));
        assertTrue(     gov.try_setValidSubFactory(address(poolFactory), address(dlFactory1), true));
        assertTrue( globals.validSubFactories(address(poolFactory), address(dlFactory1)));

        // setPoolDelegateAllowlist()
        assertTrue(!globals.isValidPoolDelegate(address(bob)));
        assertTrue(!fakeGov.try_setPoolDelegateAllowlist(address(bob), true));  // Non-governor cant set
        assertTrue(     gov.try_setPoolDelegateAllowlist(address(bob), true));
        assertTrue( globals.isValidPoolDelegate(address(bob)));
        assertTrue(     gov.try_setPoolDelegateAllowlist(address(bob), false));
        assertTrue(!globals.isValidPoolDelegate(address(bob)));

        // setDefaultUniswapPath()
        assertTrue(!fakeGov.try_setDefaultUniswapPath(WETH, USDC, USDC));  // Non-governor cant set
        assertEq(   globals.defaultUniswapPath(WETH, USDC), address(0));
        assertEq(   globals.defaultUniswapPath(DAI, USDC), address(0));
        assertTrue(     gov.try_setDefaultUniswapPath(WETH, USDC, USDC));
        assertTrue(     gov.try_setDefaultUniswapPath(DAI, USDC, WETH));
        assertEq(   globals.defaultUniswapPath(WETH, USDC), USDC);
        assertEq(   globals.defaultUniswapPath(DAI, USDC), WETH);

        // setLiquidityAsset()
        assertTrue(!globals.isValidLiquidityAsset(WETH));
        assertTrue(!fakeGov.try_setLiquidityAsset(WETH,  true));  // Non-governor cant set
        assertTrue(     gov.try_setLiquidityAsset(WETH,  true));
        assertTrue(globals.isValidLiquidityAsset(WETH));
        assertTrue(!fakeGov.try_setLiquidityAsset(WETH,  false));  // Non-governor cant set
        assertTrue(     gov.try_setLiquidityAsset(WETH,  false));
        assertTrue(!globals.isValidLiquidityAsset(WETH));

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
        assertTrue(     gov.try_setInvestorFee(5_000));     // 100% is combined upper bound
        assertTrue(     gov.try_setTreasuryFee(5_000));     // 100% is combined upper bound
        assertTrue(    !gov.try_setInvestorFee(5_001));     // 100% is combined upper bound
        assertTrue(    !gov.try_setTreasuryFee(5_001));     // 100% is combined upper bound
        assertTrue(    !gov.try_setInvestorFee(MAX_UINT));  // Attempt overflow
        assertTrue(    !gov.try_setTreasuryFee(MAX_UINT));  // Attempt overflow

        // setStakerCooldownPeriod()
        assertEq(   globals.stakerCooldownPeriod(),     10 days);
        assertTrue(!fakeGov.try_setStakerCooldownPeriod( 1 days));
        assertTrue(     gov.try_setStakerCooldownPeriod( 1 days));
        assertEq(   globals.stakerCooldownPeriod(),      1 days);

        // setLpCooldownPeriod()
        assertEq(   globals.lpCooldownPeriod(),     10 days);
        assertTrue(!fakeGov.try_setLpCooldownPeriod( 1 days));
        assertTrue(     gov.try_setLpCooldownPeriod (1 days));
        assertEq(   globals.lpCooldownPeriod(),      1 days);

        // setStakerUnstakeWindow()
        assertEq(   globals.stakerUnstakeWindow(),     2 days);
        assertTrue(!fakeGov.try_setStakerUnstakeWindow(1 days));
        assertTrue(     gov.try_setStakerUnstakeWindow(1 days));
        assertEq(   globals.stakerUnstakeWindow(),     1 days);

        // setLpWithdrawWindow()
        assertEq(   globals.lpWithdrawWindow(),     2 days);
        assertTrue(!fakeGov.try_setLpWithdrawWindow(1 days));
        assertTrue(     gov.try_setLpWithdrawWindow(1 days));
        assertEq(   globals.lpWithdrawWindow(),     1 days);

        // setFundingPeriod()
        assertEq(   globals.fundingPeriod(),    10 days);
        assertTrue(!fakeGov.try_setFundingPeriod(1 days));
        assertTrue(     gov.try_setFundingPeriod(1 days));
        assertEq(   globals.fundingPeriod(),     1 days);

        // setDefaultGracePeriod()
        assertEq(   globals.defaultGracePeriod(),     5 days);
        assertTrue(!fakeGov.try_setDefaultGracePeriod(1 days));
        assertTrue(     gov.try_setDefaultGracePeriod(1 days));
        assertEq(   globals.defaultGracePeriod(),     1 days);

        // setSwapOutRequired()
        assertEq(   globals.swapOutRequired(),     10_000);
        assertTrue(!fakeGov.try_setSwapOutRequired(15_000));
        assertTrue(    !gov.try_setSwapOutRequired( 9_999));  // Lower bound is $10,000 of pool cover
        assertTrue(     gov.try_setSwapOutRequired(15_000));
        assertEq(   globals.swapOutRequired(),     15_000);
        assertTrue(     gov.try_setSwapOutRequired(10_000));  // Lower bound is $10,000 of pool cover
        assertEq(   globals.swapOutRequired(),     10_000);

        // setMapleTreasury()
        assertEq(   globals.mapleTreasury(), address(treasury));
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

        assertTrue(globals.getLatestPrice(WETH) != 0);  // Shows real WETH value from Chainlink
        assertTrue(globals.getLatestPrice(WBTC) != 0);  // Shows real WBTC value from Chainlink

        // setMaxSwapSlippage()
        assertEq(   globals.maxSwapSlippage(),      1_000);
        assertTrue(!fakeGov.try_setMaxSwapSlippage(10_000));
        assertTrue(    !gov.try_setMaxSwapSlippage(10_001));  // 100.01% is outside of bounds
        assertTrue(     gov.try_setMaxSwapSlippage(10_000));  // 100% is upper bound
        assertEq(   globals.maxSwapSlippage(),     10_000);

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
