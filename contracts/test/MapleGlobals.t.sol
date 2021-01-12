// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "../MapleToken.sol";
import "../MapleGlobals.sol";

contract MapleGlobalsTest is TestUtil {

    ERC20        fundsToken;
    MapleToken   mpl;
    MapleGlobals globals;

    function setUp() public {
        mpl = new MapleToken("MapleToken", "MAPL", USDC);
        globals    = new MapleGlobals(address(this), address(mpl));
    }

    function test_setters() public {
        assertEq(globals.investorFee(), 50);
        globals.setInvestorFee(45);
        assertEq(globals.investorFee(), 45);

        assertEq(globals.treasuryFee(), 50);
        globals.setTreasuryFee(30);
        assertEq(globals.treasuryFee(), 30);

        assertEq(globals.gracePeriod(), 5 days);
        globals.setGracePeriod(1 days);
        assertEq(globals.gracePeriod(), 1 days);

        assertEq(globals.swapOutRequired(), 100);
        globals.setSwapOutRequired(35000);
        assertEq(globals.swapOutRequired(), 35000);

        assertEq(globals.unstakeDelay(), 90 days);
        globals.setUnstakeDelay(30 days);
        assertEq(globals.unstakeDelay(), 30 days);

        assertEq(globals.governor(), address(this));
        globals.setGovernor(address(this));
        assertEq(globals.governor(), address(this));
    }

    function test_add_tokens() public {
        string[]  memory validLoanAssetSymbols;
        address[] memory validLoanAssets;
        string[]  memory validCollateralAssetSymbols;
        address[] memory validCollateralAssets;
        (
            validLoanAssetSymbols,
            validLoanAssets,
            validCollateralAssetSymbols,
            validCollateralAssets
        ) = globals.getValidTokens();

        assertEq(validLoanAssetSymbols.length,          0);
        assertEq(validLoanAssets.length,                0);
        assertEq(validCollateralAssetSymbols.length,    0);
        assertEq(validCollateralAssets.length,          0);

        globals.setCollateralAsset(WETH, true);
        (
            validLoanAssetSymbols,
            validLoanAssets,
            validCollateralAssetSymbols,
            validCollateralAssets
        ) = globals.getValidTokens();

        assertEq(validLoanAssetSymbols.length,          0);
        assertEq(validLoanAssets.length,                0);
        assertEq(validCollateralAssetSymbols.length,    1);
        assertEq(validCollateralAssets.length,          1);
        assertEq(validCollateralAssetSymbols[0],   "WETH");
        assertEq(validCollateralAssets[0],           WETH);

        globals.setLoanAsset(USDC, true);
        (
            validLoanAssetSymbols,
            validLoanAssets,
            validCollateralAssetSymbols,
            validCollateralAssets
        ) = globals.getValidTokens();

        assertEq(validLoanAssetSymbols.length,          1);
        assertEq(validLoanAssets.length,                1);
        assertEq(validCollateralAssetSymbols.length,    1);
        assertEq(validCollateralAssets.length,          1);
        assertEq(validLoanAssetSymbols[0],          "USDC");
        assertEq(validLoanAssets[0],                  USDC);
    }
}
