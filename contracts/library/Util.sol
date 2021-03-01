// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

import "../interfaces/IERC20Details.sol";
import "../interfaces/IGlobals.sol";
import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";

/// @title Util is a library that contains utility functions.
library Util {

    using SafeMath for uint256;

    /**
        @dev Helper function for calculating min amount from a swap (adjustable for price slippage).
        @param globals   Interface of MapleGlobals
        @param fromAsset Address of ERC-20 that will be swapped
        @param toAsset   Address of ERC-20 that will returned from swap
        @param swapAmt   Amount of fromAsset to be swapped
        @return Expected amount of toAsset to receive from swap based on current oracle prices
    */
    function calcMinAmount(IGlobals globals, address fromAsset, address toAsset, uint256 swapAmt) public view returns(uint256) {
        uint256 fromAssetPrice = globals.getLatestPrice(fromAsset);
        uint256 toAssetPrice   = globals.getLatestPrice(toAsset);

        // Calculate amount out expected (abstract precision).
        uint abstractMinOut = swapAmt.mul(fromAssetPrice).div(toAssetPrice);

        // Convert to proper precision, return value.
        return abstractMinOut.mul(10 ** IERC20Details(toAsset).decimals()).div(10 ** IERC20Details(fromAsset).decimals());
    }
}
