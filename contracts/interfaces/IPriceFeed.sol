// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

interface IPriceFeed {
    function price() external view returns (uint256);
}
