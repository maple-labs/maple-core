// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "./math/math.sol";
import "./interfaces/ILoanVault.sol";

contract PremiumFlatCalculator is DSMath {

	bytes32 public calcType = "PREMIUM";
	bytes32 public name = "FLAT";

	uint256 public premiumBips;  // The amount of principal to charge extra as a premium for calling the loan.

	constructor(uint256 _premiumBips) public {
		premiumBips = _premiumBips;
	}

	/// @dev Returns the total payment, and interest/principal amount, for paying off the loan early.
	/// @return (uint,uint,uint) [0] = Principal + Interest, [1] = Principal, [2] = Interest
	function getPremiumPayment(address _loanVault) view public returns(uint256, uint256, uint256) {
		ILoanVault loan = ILoanVault(_loanVault);
		
		uint256 principalOwed = loan.principalOwed();
		uint256 interest      = mul(principalOwed, premiumBips) / 10000;

		return (add(interest, principalOwed), principalOwed, interest);
	}
} 
