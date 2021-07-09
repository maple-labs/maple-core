// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { IUsdOracle } from "./interfaces/IUsdOracle.sol";

/// @title UsdOracle is a constant price oracle feed that always returns 1 USD in 8 decimal precision.
contract UsdOracle is IUsdOracle {

    int256 constant USD_PRICE = 1 * 10 ** 8;

    function getLatestPrice() public override view returns (int256) {
        return USD_PRICE;
    }
}
