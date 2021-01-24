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
        assertTrue(globals.validPoolFactories(address(poolFactory)));
        assertTrue(globals.validLoanFactories(address(loanFactory)));
        assertTrue(globals.validSubFactories(address(poolFactory), address(slFactory)));
        assertTrue(globals.validSubFactories(address(poolFactory), address(llFactory)));
        assertTrue(globals.validSubFactories(address(poolFactory), address(dlFactory)));
        assertTrue(globals.validSubFactories(address(loanFactory), address(clFactory)));
        assertTrue(globals.validSubFactories(address(loanFactory), address(flFactory)));
    }

    function test_setters() public {

        assertTrue(!globals.validPoolFactories(address(sid)));
        gov.setValidPoolFactory(address(sid), true);
        assertTrue(globals.validPoolFactories(address(sid)));
        gov.setValidPoolFactory(address(sid), false);
        assertTrue(!globals.validPoolFactories(address(sid)));

        assertTrue(!globals.validLoanFactories(address(sid)));
        gov.setValidLoanFactory(address(sid), true);
        assertTrue(globals.validLoanFactories(address(sid)));
        gov.setValidLoanFactory(address(sid), false);
        assertTrue(!globals.validLoanFactories(address(sid)));

        assertTrue(globals.validSubFactories(address(poolFactory), address(dlFactory)));
        gov.setValidSubFactory(address(poolFactory), address(dlFactory), false);
        assertTrue(!globals.validSubFactories(address(poolFactory), address(dlFactory)));
        gov.setValidSubFactory(address(poolFactory), address(dlFactory), true);
        assertTrue(globals.validSubFactories(address(poolFactory), address(dlFactory)));
        
        assertTrue(!globals.isValidPoolDelegate(address(joe)));
        gov.setPoolDelegateWhitelist(address(joe), true);
        assertTrue(globals.isValidPoolDelegate(address(joe)));
        gov.setPoolDelegateWhitelist(address(joe), false);
        assertTrue(!globals.isValidPoolDelegate(address(joe)));

        // TODO: Assign price feeds from official ChainLink oracles.
        // TODO: Test the assignePriceFeed() and getPrice() functions.

        assertTrue(!globals.isValidLoanAsset(WETH));
        assertTrue(!globals.isValidCollateralAsset(CDAI));
        gov.setLoanAsset(WETH, true);
        gov.setCollateralAsset(CDAI, true);
        assertTrue(globals.isValidLoanAsset(WETH));
        assertTrue(globals.isValidCollateralAsset(CDAI));
        gov.setLoanAsset(WETH, false);
        gov.setCollateralAsset(CDAI, false);
        assertTrue(!globals.isValidLoanAsset(WETH));
        assertTrue(!globals.isValidCollateralAsset(CDAI));

        assertTrue(globals.isValidCalc(address(brCalc)));
        gov.setCalc(address(brCalc), false);
        assertTrue(!globals.isValidCalc(address(brCalc)));

        assertEq(globals.governor(),         address(gov));
        assertEq(globals.mpl(),              address(mpl));
        assertEq(globals.gracePeriod(),            5 days);
        assertEq(globals.swapOutRequired(),           100);
        assertEq(globals.unstakeDelay(),          90 days);
        assertEq(globals.drawdownGracePeriod(),    1 days);
        assertEq(globals.BFactory(),        BPOOL_FACTORY);

        assertEq(globals.investorFee(), 50);
        gov.setInvestorFee(30);
        assertEq(globals.investorFee(), 30);

        assertEq(globals.treasuryFee(), 50);
        gov.setTreasuryFee(30);
        assertEq(globals.treasuryFee(), 30);

        assertEq(globals.drawdownGracePeriod(), 1 days);
        gov.setDrawdownGracePeriod(3 days);
        assertEq(globals.drawdownGracePeriod(), 3 days);
        gov.setDrawdownGracePeriod(1 days);
        assertEq(globals.drawdownGracePeriod(), 1 days);

        assertEq(globals.gracePeriod(), 5 days);
        gov.setGracePeriod(3 days);
        assertEq(globals.gracePeriod(), 3 days);
        gov.setGracePeriod(7 days);
        assertEq(globals.gracePeriod(), 7 days);

        assertEq(globals.swapOutRequired(), 100);
        gov.setSwapOutRequired(100000);
        assertEq(globals.swapOutRequired(), 100000);

        assertEq(globals.unstakeDelay(), 90 days);
        gov.setUnstakeDelay(30 days);
        assertEq(globals.unstakeDelay(), 30 days);

        assertEq(globals.mapleTreasury(), address(trs));
        gov.setMapleTreasury(address(this));
        assertEq(globals.mapleTreasury(), address(this));

        gov.setGovernor(address(sid));
        assertEq(globals.governor(), address(sid));

        assertEq(globals.extendedGracePeriod(), 5 days);
        // Fail to set the extendedGracePeriod (aka EGP) because msg.sender != governor.
        assertTrue(!joe.try_setExtendedGracePeriod(address(globals), 20 days));

        // Successfully set the EGP with right governor.
        assertTrue(sid.try_setExtendedGracePeriod(address(globals), 20 days));
        assertEq(globals.extendedGracePeriod(), 20 days);
    }
}
