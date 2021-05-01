// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

interface ILateFeeCalc {

    function calcType() external view returns (uint8);

    function name() external view returns (bytes32);

    function lateFee() external view returns (uint256);

    function getLateFee(uint256) external view returns (uint256);

} 
