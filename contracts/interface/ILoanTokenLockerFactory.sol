// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

interface ILoanTokenLockerFactory {
    function newLocker(address _loanToken) external returns (address);
}
