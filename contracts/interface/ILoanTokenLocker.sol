// SPDX-License-Identifier: MIT
pragma solidity 0.7.0;

interface ILoanTokenLocker {
    function owner() external returns (address);

    function loanToken() external returns (address);

    function fetch() external;
}
