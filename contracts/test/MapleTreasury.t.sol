// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "./user/Governor.sol";
import "./user/Holder.sol";

import "../MapleTreasury.sol";

import "../interfaces/IGlobals.sol";

import "../library/Util.sol";

import "../oracles/ChainlinkOracle.sol";
import "../oracles/UsdOracle.sol";

import "module/maple-token/contracts/MapleToken.sol";

contract MapleTreasuryTest is TestUtil {

    Governor                gov;
    Governor            fakeGov;

    MapleGlobals        globals;
    MapleToken              mpl;
    MapleTreasury      treasury;
    ChainlinkOracle  wethOracle;
    ChainlinkOracle  wbtcOracle;
    UsdOracle         usdOracle;
    ChainlinkOracle   daiOracle;

    function setUp() public {
        gov     = new Governor();   // Actor: Governor of Maple.
        fakeGov = new Governor();

        mpl      = new MapleToken("MapleToken", "MAPLE", USDC);
        globals  = gov.createGlobals(address(mpl), BPOOL_FACTORY, address(0));
        treasury = new MapleTreasury(address(mpl), USDC, UNISWAP_V2_ROUTER_02, address(globals)); 

        // Set test util governor storage var
        gov.setGovTreasury(treasury);
        fakeGov.setGovTreasury(treasury);

        wethOracle = new ChainlinkOracle(tokens["WETH"].orcl, WETH, address(this));
        wbtcOracle = new ChainlinkOracle(tokens["WBTC"].orcl, WBTC, address(this));
        daiOracle  = new ChainlinkOracle(tokens["DAI"].orcl, USDC, address(this));
        usdOracle  = new UsdOracle();
        
        gov.setMapleTreasury(address(treasury));
        gov.setPriceOracle(WETH, address(wethOracle));
        gov.setPriceOracle(WBTC, address(wbtcOracle));
        gov.setPriceOracle(USDC, address(usdOracle));
        gov.setPriceOracle(DAI,  address(daiOracle));
    
        gov.setDefaultUniswapPath(WBTC, USDC, WETH);

        mint("WBTC", address(this),  10 * BTC);
        mint("WETH", address(this),  10 ether);
        mint("DAI",  address(this), 100 ether);
        mint("USDC", address(this), 100 * USD);
    }

    function test_setGlobals() public {
        MapleGlobals globals2 = fakeGov.createGlobals(address(mpl), BPOOL_FACTORY, address(0));  // Create upgraded MapleGlobals

        assertEq(address(treasury.globals()), address(globals));

        assertTrue(!fakeGov.try_setGlobals(address(treasury), address(globals2)));  // Non-governor cannot set new globals

        globals2 = gov.createGlobals(address(mpl), BPOOL_FACTORY);                  // Create upgraded MapleGlobals

        assertTrue(gov.try_setGlobals(address(treasury), address(globals2)));       // Governor can set new globals
        assertEq(address(treasury.globals()), address(globals2));                   // Globals is updated
    }

    function test_withdrawFunds() public {
        assertEq(IERC20(USDC).balanceOf(address(treasury)), 0);

        IERC20(USDC).transfer(address(treasury), 100 * USD);

        assertEq(IERC20(USDC).balanceOf(address(treasury)), 100 * USD);
        assertEq(IERC20(USDC).balanceOf(address(gov)),         0);

        assertTrue(!fakeGov.try_withdrawFunds(USDC, 40 * USD));  // Non-governor can't withdraw
        assertTrue(     gov.try_withdrawFunds(USDC, 40 * USD));

        assertEq(IERC20(USDC).balanceOf(address(treasury)), 60 * USD);  // Can be distributed to MPL holders
        assertEq(IERC20(USDC).balanceOf(address(gov)), 40 * USD);  // Withdrawn to MapleDAO address for funding
    }

    function test_distributeToHolders() public {
        Holder ali = new Holder();
        Holder bob = new Holder();

        assertEq(mpl.balanceOf(address(ali)), 0);
        assertEq(mpl.balanceOf(address(bob)), 0);

        mpl.transfer(address(ali), mpl.totalSupply() * 25 / 100);  // 25%
        mpl.transfer(address(bob), mpl.totalSupply() * 75 / 100);  // 75%

        assertEq(mpl.balanceOf(address(ali)), 2_500_000 ether);
        assertEq(mpl.balanceOf(address(bob)), 7_500_000 ether);

        assertEq(IERC20(USDC).balanceOf(address(treasury)), 0);

        IERC20(USDC).transfer(address(treasury), 100 * USD);

        assertEq(IERC20(USDC).balanceOf(address(treasury)), 100 * USD);
        assertEq(IERC20(USDC).balanceOf(address(mpl)),              0);

        assertTrue(!fakeGov.try_distributeToHolders());  // Non-governor can't distribute
        assertTrue(     gov.try_distributeToHolders());  // Governor can distribute

        assertEq(IERC20(USDC).balanceOf(address(treasury)),         0);  // Withdraws all funds
        assertEq(IERC20(USDC).balanceOf(address(mpl)),      100 * USD);  // Withdrawn to MPL address, where users can claim funds

        assertEq(IERC20(USDC).balanceOf(address(ali)), 0);  // Token holder hasn't claimed
        assertEq(IERC20(USDC).balanceOf(address(bob)), 0);  // Token holder hasn't claimed

        ali.withdrawFunds(address(mpl));
        bob.withdrawFunds(address(mpl));

        withinDiff(IERC20(USDC).balanceOf(address(ali)), 25 * USD, 1);  // Token holder has claimed proportional share of USDC
        withinDiff(IERC20(USDC).balanceOf(address(bob)), 75 * USD, 1);  // Token holder has claimed proportional share of USDC
    }

    function test_convertERC20() public {
        
        IGlobals _globals = IGlobals(address(globals));

        assertEq(IERC20(WBTC).balanceOf(address(treasury)), 0);
        assertEq(IERC20(WETH).balanceOf(address(treasury)), 0);
        assertEq(IERC20(DAI).balanceOf(address(treasury)),  0);

        IERC20(WBTC).transfer(address(treasury), 10 * BTC);
        IERC20(WETH).transfer(address(treasury), 10 ether);
        IERC20(DAI).transfer(address(treasury), 100 ether);

        assertEq(IERC20(WBTC).balanceOf(address(treasury)),  10 * BTC);
        assertEq(IERC20(WETH).balanceOf(address(treasury)),  10 ether);
        assertEq(IERC20(DAI).balanceOf(address(treasury)),  100 ether);
        assertEq(IERC20(USDC).balanceOf(address(treasury)),         0);

        uint256 expectedAmtFromWBTC = Util.calcMinAmount(_globals, WBTC, USDC,  10 * BTC);
        uint256 expectedAmtFromWETH = Util.calcMinAmount(_globals, WETH, USDC,  10 ether);
        uint256 expectedAmtFromDAI  = Util.calcMinAmount(_globals, DAI,  USDC, 100 ether);

        /*** Convert WBTC ***/
        assertTrue(!fakeGov.try_convertERC20(WBTC));  // Non-governor can't convert
        assertTrue(     gov.try_convertERC20(WBTC));  // Governor can convert

        assertEq(IERC20(WBTC).balanceOf(address(treasury)),         0);
        assertEq(IERC20(DAI).balanceOf(address(treasury)),  100 ether);

        withinPrecision(IERC20(USDC).balanceOf(address(treasury)), expectedAmtFromWBTC, 2);

        gov.distributeToHolders();  // Empty treasury balance of USDC

        /*** Convert WETH ***/
        assertTrue(!fakeGov.try_convertERC20(WETH));  // Non-governor can't convert
        assertTrue(     gov.try_convertERC20(WETH));  // Governor can convert

        assertEq(IERC20(WETH).balanceOf(address(treasury)),         0);
        assertEq(IERC20(DAI).balanceOf(address(treasury)),  100 ether);

        withinPrecision(IERC20(USDC).balanceOf(address(treasury)), expectedAmtFromWETH, 2);

        gov.distributeToHolders();  // Empty treasury balance of USDC

        /*** Convert DAI ***/
        assertTrue(!fakeGov.try_convertERC20(DAI));  // Non-governor can't convert
        assertTrue(     gov.try_convertERC20(DAI));  // Governor can convert

        assertEq(IERC20(WETH).balanceOf(address(treasury)), 0);
        assertEq(IERC20(DAI).balanceOf(address(treasury)),  0);

        withinPrecision(IERC20(USDC).balanceOf(address(treasury)), expectedAmtFromDAI, 2);
    }
}
