// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

contract UsdOracle {

    int256 constant USD_PRICE = 1 * 10 ** 8;

    /**
        @dev Returns the constant USD price.
     */
    function getLatestPrice() public pure returns (int256) {
        return USD_PRICE;
    }
}
