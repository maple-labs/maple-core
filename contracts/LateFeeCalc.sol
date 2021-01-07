// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

contract LateFeeCalc {

	bytes32 public calcType = 'LATEFEE';
	bytes32 public name = 'NULL';

	/// @dev Returns a null tuple (0,0,0) depicting the amount owed, which is 0.
	/// @notice For standardization purposes, leave loan parameter in place, even if unused.
	/// @param loan The address of the Loan (keep in place for standardization).
	/// @return [0] = Total Amount, [1] = Principal, [2] = Interest
	function getLateFee(address loan) pure public returns(uint256, uint256, uint256) {
		return (0, 0, 0);
	}
} 
