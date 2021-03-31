// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

import "./interfaces/ILoan.sol";

import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";

/// @title PremiumCalc calculates premium fees on Loans.
contract PremiumCalc {

    using SafeMath for uint256;

    uint8   public constant calcType = 12;      // PREMIUM type
    bytes32 public constant name     = "FLAT";
    
    uint256 public immutable premiumFee;  // Flat percentage fee (in basis points) of principal to charge as a premium when calling a Loan

    constructor(uint256 _premiumFee) public {
        premiumFee = _premiumFee;
    }

    /**
        @dev    Calculates the premium payment for a Loan, when making a full payment.
        @param  _loan Loan to calculate a premium payment for
        @return [0] = Principal + Interest
                [1] = Principal
                [2] = Interest
    */
    function getPremiumPayment(address _loan) view public returns(uint256, uint256, uint256) {
        ILoan   loan          = ILoan(_loan);
        uint256 principalOwed = loan.principalOwed();
        uint256 interest      = principalOwed.mul(premiumFee).div(10_000);
        return (interest.add(principalOwed), principalOwed, interest);
    }
} 
