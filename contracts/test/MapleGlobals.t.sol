// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "./user/Governor.sol";

import "../MapleToken.sol";
import "../PoolFactory.sol";
import "../LoanFactory.sol";
import "../DebtLockerFactory.sol";
import "../StakeLockerFactory.sol";
import "../LiquidityLockerFactory.sol";
import "../FundingLockerFactory.sol";
import "../CollateralLockerFactory.sol";
import "../MapleTreasury.sol";
import "../LateFeeCalc.sol";
import "../PremiumCalc.sol";
import "../BulletRepaymentCalc.sol";

contract PoolDelegate { 

    function try_setExtendedGracePeriod(address globals, uint256 newEGP) external returns(bool ok) {
        string memory sig = "setExtendedGracePeriod(uint256)";
        (ok,) = globals.call(abi.encodeWithSignature(sig, newEGP));
    }
}

contract MapleGlobalsTest is TestUtil {

    Governor                         gov;
    ERC20                     fundsToken;
    MapleToken                       mpl;
    MapleGlobals                 globals;
    FundingLockerFactory       flFactory;
    CollateralLockerFactory    clFactory;
    LoanFactory              loanFactory;
    PoolFactory              poolFactory;
    StakeLockerFactory         slFactory;
    LiquidityLockerFactory     llFactory; 
    DebtLockerFactory          dlFactory;
    BulletRepaymentCalc           brCalc;
    LateFeeCalc                   lfCalc;
    PremiumCalc                    pCalc;
    PoolDelegate                     sid;
    PoolDelegate                     joe;
    MapleTreasury                    trs;

    function setUp() public {

        gov         = new Governor();
        mpl         = new MapleToken("MapleToken", "MAPLE", USDC);
        globals     = gov.createGlobals(address(mpl), BPOOL_FACTORY);
        poolFactory = new PoolFactory(address(globals));
        loanFactory = new LoanFactory(address(globals));
        dlFactory   = new DebtLockerFactory();
        slFactory   = new StakeLockerFactory();
        llFactory   = new LiquidityLockerFactory();
        flFactory   = new FundingLockerFactory();
        clFactory   = new CollateralLockerFactory();
        lfCalc      = new LateFeeCalc(0);
        pCalc       = new PremiumCalc(200);
        brCalc      = new BulletRepaymentCalc();
        sid         = new PoolDelegate();
        joe         = new PoolDelegate();
        trs         = new MapleTreasury(address(mpl), USDC, UNISWAP_V2_ROUTER_02, address(globals)); 

        // The following code was adopted from maple-core/scripts/setup.js
        gov.setMapleTreasury(address(trs));
        gov.setPoolDelegateWhitelist(address(sid), true);
        gov.setLoanAsset(DAI, true);
        gov.setLoanAsset(USDC, true);
        gov.setCollateralAsset(DAI, true);
        gov.setCollateralAsset(USDC, true);
        gov.setCollateralAsset(WETH, true);
        gov.setCollateralAsset(WBTC, true);

        // TODO: Assign price feeds from official ChainLink oracles.

        gov.setCalc(address(lfCalc), true);
        gov.setCalc(address(pCalc), true);
        gov.setCalc(address(brCalc), true);

        gov.setValidPoolFactory(address(poolFactory), true);
        gov.setValidLoanFactory(address(loanFactory), true);

        gov.setValidSubFactory(address(poolFactory), address(slFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(llFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(dlFactory), true);
        gov.setValidSubFactory(address(loanFactory), address(clFactory), true);
        gov.setValidSubFactory(address(loanFactory), address(flFactory), true);
    }

    function test_constructor() public {
        assertEq(globals.mapleTreasury(),    address(trs));
        assertEq(globals.governor(),         address(gov));
        assertEq(globals.mpl(),              address(mpl));
        assertEq(globals.gracePeriod(),            5 days);
        assertEq(globals.swapOutRequired(),           100);
        assertEq(globals.unstakeDelay(),          90 days);
        assertEq(globals.drawdownGracePeriod(),    1 days);
        assertEq(globals.investorFee(),                50);
        assertEq(globals.treasuryFee(),                50);
        assertEq(globals.BFactory(),        BPOOL_FACTORY);
    }

    function test_setup() public {
        assertTrue(globals.isValidPoolDelegate(address(sid)));
        assertTrue(globals.isValidLoanAsset(DAI));
        assertTrue(globals.isValidLoanAsset(USDC));
        assertTrue(globals.isValidCollateralAsset(DAI));
        assertTrue(globals.isValidCollateralAsset(USDC));
        assertTrue(globals.isValidCollateralAsset(WETH));
        assertTrue(globals.isValidCollateralAsset(WBTC));
        assertTrue(globals.isValidCalc(address(lfCalc)));
        assertTrue(globals.isValidCalc(address(pCalc)));
        assertTrue(globals.isValidCalc(address(brCalc)));
        assertTrue(globals.isValidPoolFactory(address(poolFactory)));
        assertTrue(globals.isValidLoanFactory(address(loanFactory)));
        assertTrue(globals.validSubFactories(address(poolFactory), address(slFactory)));
        assertTrue(globals.validSubFactories(address(poolFactory), address(llFactory)));
        assertTrue(globals.validSubFactories(address(poolFactory), address(dlFactory)));
        assertTrue(globals.validSubFactories(address(loanFactory), address(clFactory)));
        assertTrue(globals.validSubFactories(address(loanFactory), address(flFactory)));
    }

    function test_setters() public {

        Governor fakeGov = new Governor();
        fakeGov.setGovGlobals(globals);  // Point to globals created by gov

        // setValidPoolFactory()
        assertTrue(!globals.isValidPoolFactory(address(sid)));             // Use dummy address since poolFactory is already valid
        assertTrue(!fakeGov.try_setValidPoolFactory(address(sid), true));  // Non-governor cant set
        assertTrue(     gov.try_setValidPoolFactory(address(sid), true));
        assertTrue(globals.isValidPoolFactory(address(sid)));
        assertTrue(gov.try_setValidPoolFactory(address(sid), false));
        assertTrue(!globals.isValidPoolFactory(address(sid)));

        // setValidLoanFactory()
        assertTrue(!globals.isValidLoanFactory(address(sid)));             // Use dummy address since loanFactory is already valid
        assertTrue(!fakeGov.try_setValidLoanFactory(address(sid), true));  // Non-governor cant set
        assertTrue(     gov.try_setValidLoanFactory(address(sid), true));
        assertTrue(globals.isValidLoanFactory(address(sid)));
        assertTrue(gov.try_setValidLoanFactory(address(sid), false));
        assertTrue(!globals.isValidLoanFactory(address(sid)));

        // setValidSubFactory()
        assertTrue(globals.validSubFactories(address(poolFactory), address(dlFactory)));
        assertTrue(!fakeGov.try_setValidSubFactory(address(poolFactory), address(dlFactory), false));  // Non-governor cant set
        assertTrue(     gov.try_setValidSubFactory(address(poolFactory), address(dlFactory), false));
        assertTrue(!globals.validSubFactories(address(poolFactory), address(dlFactory)));
        assertTrue(gov.try_setValidSubFactory(address(poolFactory), address(dlFactory), true));
        assertTrue(globals.validSubFactories(address(poolFactory), address(dlFactory)));
        
        assertTrue(!globals.isValidPoolDelegate(address(joe)));
        assertTrue(!fakeGov.try_setPoolDelegateWhitelist(address(joe), true));  // Non-governor cant set
        assertTrue(     gov.try_setPoolDelegateWhitelist(address(joe), true));
        assertTrue(globals.isValidPoolDelegate(address(joe)));
        assertTrue(gov.try_setPoolDelegateWhitelist(address(joe), false));
        assertTrue(!globals.isValidPoolDelegate(address(joe)));

        // TODO: Assign price feeds from official ChainLink oracles.
        // TODO: Test the assignePriceFeed() and getPrice() functions.

        assertTrue(!globals.isValidLoanAsset(WETH));
        assertTrue(!globals.isValidCollateralAsset(CDAI));
        assertTrue(!fakeGov.try_setLoanAsset(WETH,       true));  // Non-governor cant set
        assertTrue(     gov.try_setLoanAsset(WETH,       true));
        assertTrue(!fakeGov.try_setCollateralAsset(CDAI, true));  // Non-governor cant set
        assertTrue(     gov.try_setCollateralAsset(CDAI, true));
        assertTrue(globals.isValidLoanAsset(WETH));
        assertTrue(globals.isValidCollateralAsset(CDAI));
        assertTrue(!fakeGov.try_setLoanAsset(WETH,       false));  // Non-governor cant set
        assertTrue(     gov.try_setLoanAsset(WETH,       false));
        assertTrue(!fakeGov.try_setCollateralAsset(CDAI, false));  // Non-governor cant set
        assertTrue(     gov.try_setCollateralAsset(CDAI, false));
        assertTrue(!globals.isValidLoanAsset(WETH));
        assertTrue(!globals.isValidCollateralAsset(CDAI));

        assertTrue(globals.isValidCalc(address(brCalc)));
        assertTrue(!fakeGov.try_setCalc(address(brCalc), false));  // Non-governor cant set
        assertTrue(     gov.try_setCalc(address(brCalc), false));
        assertTrue(!globals.isValidCalc(address(brCalc)));

        assertEq(globals.governor(),         address(gov));
        assertEq(globals.mpl(),              address(mpl));
        assertEq(globals.gracePeriod(),            5 days);
        assertEq(globals.swapOutRequired(),           100);
        assertEq(globals.unstakeDelay(),          90 days);
        assertEq(globals.drawdownGracePeriod(),    1 days);
        assertEq(globals.BFactory(),        BPOOL_FACTORY);

        assertEq(globals.investorFee(), 50);
        assertTrue(!fakeGov.try_setInvestorFee(30));  // Non-governor cant set
        assertTrue(     gov.try_setInvestorFee(30));
        assertEq(globals.investorFee(), 30);

        assertEq(globals.treasuryFee(), 50);
        assertTrue(!fakeGov.try_setTreasuryFee(30));  // Non-governor cant set
        assertTrue(     gov.try_setTreasuryFee(30));
        assertEq(globals.treasuryFee(), 30);

        assertEq(globals.drawdownGracePeriod(), 1 days);
        assertTrue(!fakeGov.try_setDrawdownGracePeriod(3 days));
        assertTrue(     gov.try_setDrawdownGracePeriod(3 days));
        assertEq(globals.drawdownGracePeriod(), 3 days);
        assertTrue(!fakeGov.try_setDrawdownGracePeriod(1 days));
        assertTrue(     gov.try_setDrawdownGracePeriod(1 days));
        assertEq(globals.drawdownGracePeriod(), 1 days);

        assertEq(globals.gracePeriod(), 5 days);
        assertTrue(!fakeGov.try_setGracePeriod(3 days));
        assertTrue(     gov.try_setGracePeriod(3 days));
        assertEq(globals.gracePeriod(), 3 days);
        assertTrue(!fakeGov.try_setGracePeriod(7 days));
        assertTrue(     gov.try_setGracePeriod(7 days));
        assertEq(globals.gracePeriod(), 7 days);

        assertEq(globals.swapOutRequired(), 100);
        assertTrue(!fakeGov.try_setSwapOutRequired(100000));
        assertTrue(     gov.try_setSwapOutRequired(100000));
        assertEq(globals.swapOutRequired(), 100000);

        assertEq(globals.unstakeDelay(), 90 days);
        assertTrue(!fakeGov.try_setUnstakeDelay(30 days));
        assertTrue(     gov.try_setUnstakeDelay(30 days));
        assertEq(globals.unstakeDelay(), 30 days);

        assertEq(globals.mapleTreasury(), address(trs));
        assertTrue(!fakeGov.try_setMapleTreasury(address(this)));
        assertTrue(     gov.try_setMapleTreasury(address(this)));
        assertEq(globals.mapleTreasury(), address(this));

        assertEq(globals.extendedGracePeriod(),  5 days);
        assertTrue(!fakeGov.try_setUnstakeDelay(20 days));
        assertTrue(     gov.try_setUnstakeDelay(20 days));
        assertEq(globals.unstakeDelay(),        20 days);

        assertTrue(!fakeGov.try_setPriceOracle(WETH, address(1)));
        assertTrue(     gov.try_setPriceOracle(WETH, 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419));
        assertTrue(     gov.try_setPriceOracle(WBTC, 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c));
        assertEq(globals.oracleFor(WETH),             0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
        assertEq(globals.oracleFor(WBTC),             0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c);

        // assertEq(globals.getLatestPrice(WETH), 0); // Shows real WETH value from ChainLink
        // assertEq(globals.getLatestPrice(WBTC), 0); // Shows real WBTC value from ChainLink

        assertTrue(!fakeGov.try_setGovernor(address(fakeGov)));
        assertTrue(     gov.try_setGovernor(address(fakeGov)));
        assertEq(globals.governor(), address(fakeGov));
        assertTrue(fakeGov.try_setGovernor(address(gov)));  // Assert new governor has permissions
        assertEq(globals.governor(), address(gov));
    }
}
