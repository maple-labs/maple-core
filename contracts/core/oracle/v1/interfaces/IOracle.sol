// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

/// @title Oracle is a price oracle feed.
interface IOracle {

    /**
        @dev Returns the price of the asset.
     */
    function getLatestPrice() external view returns (int256);
}
