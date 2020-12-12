// SPDX-License-Identifier: MIT
pragma solidity 0.7.0;

interface ILoanTokenLockerFactory {
    function newLocker(address _loanToken) external returns (address);
}
