// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "./user/Governor.sol";
import "./user/Holder.sol";

import "../MapleToken.sol";
import "../MapleTreasury.sol";

contract MapleTreasuryTest is TestUtil {

    Governor           gov;
    Governor       fakeGov;

    MapleGlobals   globals;
    MapleToken         mpl;
    MapleTreasury treasury;

    function setUp() public {

        gov     = new Governor();   // Actor: Governor of Maple.
        fakeGov = new Governor();

        mpl      = new MapleToken("MapleToken", "MAPLE", USDC);
        globals  = gov.createGlobals(address(mpl), BPOOL_FACTORY);
        treasury = new MapleTreasury(address(mpl), USDC, UNISWAP_V2_ROUTER_02, address(globals)); 

        // Set test util governor storage var
        gov.setGovTreasury(treasury);
        fakeGov.setGovTreasury(treasury);

        gov.setMapleTreasury(address(treasury));
        gov.setPriceOracle(WETH, 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
        gov.setPriceOracle(WBTC, 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c);
        gov.setPriceOracle(USDC, 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9);

        mint("WETH", address(this), 10 ether);
        mint("USDC", address(this), 100 * USD);
    }

    function test_setGlobals() public {
        MapleGlobals globals2 = fakeGov.createGlobals(address(mpl), BPOOL_FACTORY);  // Create upgraded MapleGlobals

        assertEq(address(treasury.globals()), address(globals));

        assertTrue(!fakeGov.try_setGlobals(address(treasury), address(globals2)));  // Non-governor cannot set new globals

        globals2 = gov.createGlobals(address(mpl), BPOOL_FACTORY);             // Create upgraded MapleGlobals

        assertTrue(gov.try_setGlobals(address(treasury), address(globals2)));       // Governor can set new globals
        assertEq(address(treasury.globals()), address(globals2));                   // Globals is updated
    }

    function test_withdrawFunds() public {
        assertEq(IERC20(USDC).balanceOf(address(treasury)), 0);

        IERC20(USDC).transfer(address(treasury), 100 * USD);

        assertEq(IERC20(USDC).balanceOf(address(treasury)), 100 * USD);
        assertEq(IERC20(USDC).balanceOf(address(gov)),         0);

        assertTrue(!fakeGov.try_withdrawFunds(40 * USD));  // Non-governor can't withdraw
        assertTrue(     gov.try_withdrawFunds(40 * USD));

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
}
