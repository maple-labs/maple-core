pragma solidity 0.7.0;

interface ILoanVaultFactory {
  function isLoanVault(address) external view returns (bool);
}