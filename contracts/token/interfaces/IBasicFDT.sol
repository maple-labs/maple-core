// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "./IBaseFDT.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IBasicFDT is IBaseFDT, IERC20 {
    event PointsPerShareUpdated(uint256);

    event PointsCorrectionUpdated(address indexed, int256);

    function withdrawnFundsOf(address) external view returns (uint256);

    function accumulativeFundsOf(address) external view returns (uint256);

    function updateFundsReceived() external;
}
