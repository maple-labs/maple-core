// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "../interfaces/IERC20Details.sol";
import "../interfaces/IGlobals.sol";
import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";

library Util {

    using SafeMath for uint256;

    /**
        @dev Helper function for calculating min amount from a swap (adjustable for price slippage).
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