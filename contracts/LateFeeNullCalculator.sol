// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

contract LateFeeNullCalculator {

  bytes32 public calcType = 'LATEFEE';
  bytes32 public name = 'NULL';

  /// @dev Returns a null tuple (0,0,0) depicting the amount owed, which is 0.
  /// @notice For standardization purposes, leave _loanVault parameter in place, even if unused.
  /// @param _loanVault The address of the LoanVault (keep in place for standardization).
  /// @return [0] = Total Amount, [1] = Principal, [2] = Interest
  function getLateFee(address _loanVault) pure public returns(uint256, uint256, uint256) {
      return (0, 0, 0);
  }
} 
