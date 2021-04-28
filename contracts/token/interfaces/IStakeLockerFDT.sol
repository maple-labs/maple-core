// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "./IExtendedFDT.sol";
import "./IERC2258.sol";

interface IStakeLockerFDT is IExtendedFDT, IERC2258 {
    function lossesSum() external view returns (uint256);

    function lossesBalance() external view returns (uint256);
}
