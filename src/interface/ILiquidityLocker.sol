// SPDX-License-Identifier: MIT
pragma solidity ^0.6.11;

interface ILiquidityLocker {
    function fundLoan(address _loanVault,address _loanTokenLocker, uint256 _amt) external;
}
