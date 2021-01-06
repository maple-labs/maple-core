// SPDX-License-Identifier: MIT
pragma solidity >=0.6.7;

interface ILiquidityLocker {
    function fundLoan(address _loanVault,address _loanTokenLocker, uint256 _amt) external;
    function transfer(address _to, uint256 _amt) external returns (bool);
}
