// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "test/TestUtil.sol";

contract MapleTreasuryTest is TestUtil {

    function setUp() public {
        setUpGlobals();
        setUpTokens();
        setUpOracles();
        createHolders();

        mint("WBTC", address(this),  10 * BTC);
        mint("WETH", address(this),  10 ether);
        mint("DAI",  address(this), 100 ether);
        mint("USDC", address(this), 100 * USD);
    }

    function test_setGlobals() public {
        MapleGlobals globals2 = fakeGov.createGlobals(address(mpl));                // Create upgraded MapleGlobals

        assertEq(address(treasury.globals()), address(globals));

        assertTrue(!fakeGov.try_setGlobals(address(treasury), address(globals2)));  // Non-governor cannot set new globals

        globals2 = gov.createGlobals(address(mpl));                                 // Create upgraded MapleGlobals

        assertTrue(gov.try_setGlobals(address(treasury), address(globals2)));       // Governor can set new globals
        assertEq(address(treasury.globals()), address(globals2));                   // Globals is updated
    }

    function test_withdrawFunds() public {
        assertEq(IERC20(USDC).balanceOf(address(treasury)), 0);

        IERC20(USDC).transfer(address(treasury), 100 * USD);

        assertEq(IERC20(USDC).balanceOf(address(treasury)), 100 * USD);
        assertEq(IERC20(USDC).balanceOf(address(gov)),         0);

        assertTrue(!fakeGov.try_reclaimERC20_treasury(USDC, 40 * USD));  // Non-governor can't withdraw
        assertTrue(     gov.try_reclaimERC20_treasury(USDC, 40 * USD));

        assertEq(IERC20(USDC).balanceOf(address(treasury)), 60 * USD);  // Can be distributed to MPL holders
        assertEq(IERC20(USDC).balanceOf(address(gov)), 40 * USD);  // Withdrawn to MapleDAO address for funding
    }

    function test_distributeToHolders() public {
        assertEq(mpl.balanceOf(address(hal)), 0);
        assertEq(mpl.balanceOf(address(hue)), 0);

        mpl.transfer(address(hal), mpl.totalSupply() * 25 / 100);  // 25%
        mpl.transfer(address(hue), mpl.totalSupply() * 75 / 100);  // 75%

        assertEq(mpl.balanceOf(address(hal)), 2_500_000 ether);
        assertEq(mpl.balanceOf(address(hue)), 7_500_000 ether);

        assertEq(IERC20(USDC).balanceOf(address(treasury)), 0);

        IERC20(USDC).transfer(address(treasury), 100 * USD);

        assertEq(IERC20(USDC).balanceOf(address(treasury)), 100 * USD);
        assertEq(IERC20(USDC).balanceOf(address(mpl)),              0);

        assertTrue(!fakeGov.try_distributeToHolders());  // Non-governor can't distribute
        assertTrue(     gov.try_distributeToHolders());  // Governor can distribute

        assertEq(IERC20(USDC).balanceOf(address(treasury)),         0);  // Withdraws all funds
        assertEq(IERC20(USDC).balanceOf(address(mpl)),      100 * USD);  // Withdrawn to MPL address, where accounts can claim funds

        assertEq(IERC20(USDC).balanceOf(address(hal)), 0);  // Token holder hasn't claimed
        assertEq(IERC20(USDC).balanceOf(address(hue)), 0);  // Token holder hasn't claimed

        hal.withdrawFunds(address(mpl));
        hue.withdrawFunds(address(mpl));

        withinDiff(IERC20(USDC).balanceOf(address(hal)), 25 * USD, 1);  // Token holder has claimed proportional share of USDC
        withinDiff(IERC20(USDC).balanceOf(address(hue)), 75 * USD, 1);  // Token holder has claimed proportional share of USDC
    }

    function test_convertERC20() public {

        IMapleGlobals _globals = IMapleGlobals(address(globals));

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
