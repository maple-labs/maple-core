// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

interface ILoanFactory {
    function isLoan(address) external view returns (bool);
    function loans(uint256)  external view returns (address);
    function globals()       external view returns (address);
}
