// SPDX-License-Identifier: MIT
pragma solidity >=0.6.7;

interface ILiquidityLocker {
    function fundLoan(address _loanVault,address _DebtLocker, uint256 _amt) external;
}
