// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "core/oracle/v1/Oracle.sol";

import "./interfaces/IUsdOracle.sol";

/// @title UsdOracle is a constant price oracle feed that always returns 1 USD in 8 decimal precision.
contract UsdOracle is IUsdOracle, Oracle {

    int256 constant USD_PRICE = 1 * 10 ** 8;

    function getLatestPrice() public override(IUsdOracle, Oracle) view returns (int256) {
        return USD_PRICE;
    }
}
