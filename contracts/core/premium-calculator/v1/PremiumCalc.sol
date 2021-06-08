// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "../../../../lib/openzeppelin-contracts/contracts/math/SafeMath.sol";

import "../../loan/v1/interfaces/ILoan.sol";

/// @title PremiumCalc calculates premium fees on Loans.
contract PremiumCalc {

    using SafeMath for uint256;

    uint8   public constant calcType = 12;      // PREMIUM type.
    bytes32 public constant name     = "FLAT";

    uint256 public immutable premiumFee;  // Flat percentage fee (in basis points) of principal to charge as a premium when calling a Loan.

    constructor(uint256 _premiumFee) public {
        premiumFee = _premiumFee;
    }

    /**
        @dev    Calculates the premium payment for a Loan, when making a full payment.
        @param  _loan         The address of a Loan to calculate a premium payment for.
        @return total         Principal + Interest.
        @return principalOwed Principal.
        @return interest      Interest.
    */
    function getPremiumPayment(address _loan) external view returns (uint256 total, uint256 principalOwed, uint256 interest) {
        principalOwed = ILoan(_loan).principalOwed();
        interest      = principalOwed.mul(premiumFee).div(10_000);
        total         = interest.add(principalOwed);
    }

}
