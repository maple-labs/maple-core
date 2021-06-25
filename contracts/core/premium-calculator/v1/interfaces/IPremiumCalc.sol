// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

/// @title PremiumCalc calculates premium fees on Loans.
interface IPremiumCalc {

    /**
        @dev The Calculator type: PREMIUM type.
     */
    function calcType() external view returns (uint8);

    /**
        @dev The name of the Calculator.
     */
    function name() external view returns (bytes32);

    /**
        @dev The flat percentage fee (in basis points) of principal to charge as a premium when calling a Loan.
     */
    function premiumFee() external view returns (uint256);

    /**
        @dev    Calculates the premium payment for a Loan, when making a full payment.
        @param  _loan         The address of a Loan to calculate a premium payment for.
        @return total         The principal + interest.
        @return principalOwed The principal.
        @return interest      The interest.
     */
    function getPremiumPayment(address _loan) external view returns (uint256 total, uint256 principalOwed, uint256 interest);

}
