// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

interface IPremiumCalc {
    function getPremiumPayment(address) external view returns (uint256, uint256, uint256);
} 
