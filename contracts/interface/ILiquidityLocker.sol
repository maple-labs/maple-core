// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface ILiquidityLocker {
    function fundLoan(address _loanVault, uint256 _amt) external;
}