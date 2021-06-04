// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

interface IRepaymentCalc {

    function calcType() external view returns (uint8);

    function name() external view returns (bytes32);

    function getNextPayment(address) external view returns (uint256, uint256, uint256);

}
