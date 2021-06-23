// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "./interfaces/IOracle.sol";

/// @title Oracle is a price oracle feed.
abstract contract Oracle is IOracle {

    function getLatestPrice() external override virtual view returns (int256);

}
