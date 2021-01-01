// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

interface ILoanTokenLocker {
    function owner() external returns (address);

    function loanToken() external returns (address);

    function fetch() external;

    function claim() external;
}
