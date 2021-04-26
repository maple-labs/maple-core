// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

interface IPremiumCalc {
    function calcType() external view returns (uint8);

    function name() external view returns (bytes32);

    function premiumFee() external view returns (uint256);

    function getPremiumPayment(address) external view returns (uint256, uint256, uint256);
} 
