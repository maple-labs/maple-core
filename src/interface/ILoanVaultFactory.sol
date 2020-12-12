// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

interface ILoanVaultFactory {
    function isLoanVault(address) external view returns (bool);
}
