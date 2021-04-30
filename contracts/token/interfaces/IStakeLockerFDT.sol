// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "./IExtendedFDT.sol";

interface IStakeLockerFDT is IExtendedFDT {

    function fundsToken() external view returns (address);

    function fundsTokenBalance() external view returns (uint256);

    function bptLosses() external view returns (uint256);

    function lossesBalance() external view returns (uint256);

}
