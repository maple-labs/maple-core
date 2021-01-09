// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "./interfaces/ILoan.sol";

/// @title PremiumCalc applies a flat fee on the princpal owed when paying off the loan in full.
contract PremiumCalc {

    using SafeMath for uint256;

    bytes32 public calcType = "PREMIUM";
    bytes32 public name = "FLAT";
    
    uint256 public premiumBips;  // The amount of principal to charge extra as a premium for calling the loan.

    constructor(uint256 _premiumBips) public {
        premiumBips = _premiumBips;
    }

    /// @dev Returns the total payment, and interest/principal amount, for paying off the loan early.
    /// @return (uint,uint,uint) [0] = Principal + Interest, [1] = Principal, [2] = Interest
    function getPremiumPayment(address _loan) view public returns(uint256, uint256, uint256) {
        ILoan   loan          = ILoan(_loan);
        uint256 principalOwed = loan.principalOwed();
        uint256 interest      = principalOwed.mul(premiumBips).div(10000);
        return (interest.add(principalOwed), principalOwed, interest);
    }
} 
