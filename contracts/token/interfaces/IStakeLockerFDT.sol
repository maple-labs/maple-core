// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "./IExtendedFDT.sol";
import "./IFDT.sol";

interface IStakeLockerFDT is IExtendedFDT, IFDT {
    function bptLosses() external view returns(uint256);

    function lossesBalance() external view returns(uint256);
}
