// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "../../../../core/oracle/v1/interfaces/IOracle.sol";

/// @title UsdOracle is a constant price oracle feed that always returns 1 USD in 8 decimal precision.
interface IUsdOracle is IOracle {

    /**
        @dev Returns the constant USD price.
     */
    function getLatestPrice() external override view returns (int256);
    
}
