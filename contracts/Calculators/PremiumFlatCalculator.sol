// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "../interface/ILoanVault.sol";

contract PremiumFlatCalculator {

	using SafeMath for uint256;

  /// @notice The amount of principal to charge extra as a premium for calling the loan.
  uint256 public premiumBips;

  constructor(uint256 _premiumBips) public {
      premiumBips = _premiumBips;
  }

  /// @dev Returns the total payment, and interest/principal amount, for paying off the loan early.
  /// @return (uint,uint,uint) [0] = Principal + Interest, [1] = Principal, [2] = Interest
  function getPremiumPayment(address _loanVault) view public returns(uint256, uint256, uint256) {

    ILoanVault loan = ILoanVault(_loanVault);
    uint256 principalOwed = loan.principalOwed();
    uint256 interest = principalOwed.mul(premiumBips).div(10000);
    
    return (interest.add(principalOwed), principalOwed, interest);

  }

} 
