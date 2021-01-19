// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "../MapleToken.sol";
import "../MapleGlobals.sol";
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

contract PoolDelegate { }

contract MapleGlobalsTest is TestUtil {

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
    MapleTreasury                    trs;

    function setUp() public {
        mpl         = new MapleToken("MapleToken", "MAPLE", USDC);
        globals     = new MapleGlobals(address(this), address(mpl), BPOOL_FACTORY);
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
        trs         = new MapleTreasury(address(mpl), USDC, UNISWAP_V2_ROUTER_02, address(globals)); 

        // The following code was adopted from maple-core/scripts/setup.js
        globals.setPoolDelegateWhitelist(address(sid), true);
        globals.setLoanAsset(DAI, true);
        globals.setLoanAsset(USDC, true);
        globals.setCollateralAsset(DAI, true);
        globals.setCollateralAsset(USDC, true);
        globals.setCollateralAsset(WETH, true);
        globals.setCollateralAsset(WBTC, true);

        // TODO: Assign price feeds from official ChainLink oracles.

        globals.setCalc(address(lfCalc), true);
        globals.setCalc(address(pCalc), true);
        globals.setCalc(address(brCalc), true);

        globals.setValidPoolFactory(address(poolFactory), true);
        globals.setValidLoanFactory(address(loanFactory), true);

        // TODO: Assign DebtLockerFactory within validSubFactory mapping (relates to SC-1272)

        globals.setValidSubFactory(address(poolFactory), address(slFactory), true);
        globals.setValidSubFactory(address(poolFactory), address(llFactory), true);
        globals.setValidSubFactory(address(loanFactory), address(clFactory), true);
        globals.setValidSubFactory(address(loanFactory), address(flFactory), true);
    }

    function test_constructor() public {
        assertEq(globals.governor(),        address(this));
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
        
    }

    function test_setters() public {
        
        globals.setInvestorFee(45);
        assertEq(globals.investorFee(), 45);

        globals.setTreasuryFee(30);
        assertEq(globals.treasuryFee(), 30);

        globals.setGracePeriod(1 days);
        assertEq(globals.gracePeriod(), 1 days);

        globals.setSwapOutRequired(35000);
        assertEq(globals.swapOutRequired(), 35000);

        globals.setUnstakeDelay(30 days);
        assertEq(globals.unstakeDelay(), 30 days);

        globals.setGovernor(address(mpl));
        assertEq(globals.governor(), address(mpl));
    }

    function test_add_tokens() public {
        // string[]  memory validLoanAssetSymbols;
        // address[] memory validLoanAssets;
        // string[]  memory validCollateralAssetSymbols;
        // address[] memory validCollateralAssets;
        // (
        //     validLoanAssetSymbols,
        //     validLoanAssets,
        //     validCollateralAssetSymbols,
        //     validCollateralAssets
        // ) = globals.getValidTokens();

        // assertEq(validLoanAssetSymbols.length,          0);
        // assertEq(validLoanAssets.length,                0);
        // assertEq(validCollateralAssetSymbols.length,    0);
        // assertEq(validCollateralAssets.length,          0);

        // globals.setCollateralAsset(WETH, true);
        // (
        //     validLoanAssetSymbols,
        //     validLoanAssets,
        //     validCollateralAssetSymbols,
        //     validCollateralAssets
        // ) = globals.getValidTokens();

        // assertEq(validLoanAssetSymbols.length,          0);
        // assertEq(validLoanAssets.length,                0);
        // assertEq(validCollateralAssetSymbols.length,    1);
        // assertEq(validCollateralAssets.length,          1);
        // assertEq(validCollateralAssetSymbols[0],   "WETH");
        // assertEq(validCollateralAssets[0],           WETH);

        // globals.setLoanAsset(USDC, true);
        // (
        //     validLoanAssetSymbols,
        //     validLoanAssets,
        //     validCollateralAssetSymbols,
        //     validCollateralAssets
        // ) = globals.getValidTokens();

        // assertEq(validLoanAssetSymbols.length,          1);
        // assertEq(validLoanAssets.length,                1);
        // assertEq(validCollateralAssetSymbols.length,    1);
        // assertEq(validCollateralAssets.length,          1);
        // assertEq(validLoanAssetSymbols[0],          "USDC");
        // assertEq(validLoanAssets[0],                  USDC);
    }
}
