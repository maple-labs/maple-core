// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "../interfaces/IERC20Details.sol";
import "../interfaces/IMapleGlobals.sol";
import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";

/// @title Util is a library that contains utility functions.
library Util {

    using SafeMath for uint256;

    /**
        @dev    Helper function for calculating min amount from a swap (adjustable for price slippage).
        @param  globals   Interface of MapleGlobals.
        @param  fromAsset Address of ERC-20 that will be swapped.
        @param  toAsset   Address of ERC-20 that will returned from swap.
        @param  swapAmt   Amount of fromAsset to be swapped.
        @return Expected amount of toAsset to receive from swap based on current oracle prices.
    */
    function calcMinAmount(IMapleGlobals globals, address fromAsset, address toAsset, uint256 swapAmt) external view returns(uint256) {
        return 
            swapAmt
                .mul(globals.getLatestPrice(fromAsset))           // Convert from "from" asset value
                .mul(10 ** IERC20Details(toAsset).decimals())     // Convert to "to" asset decimal precision
                .div(globals.getLatestPrice(toAsset))             // Convert to "to" asset value
                .div(10 ** IERC20Details(fromAsset).decimals());  // Convert from "from" asset decimal precision
    }
}
