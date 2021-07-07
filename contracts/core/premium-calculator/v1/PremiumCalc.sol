// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";

import "core/loan/v1/interfaces/ILoan.sol";

import "./interfaces/IPremiumCalc.sol";

/// @title PremiumCalc calculates premium fees on Loans.
contract PremiumCalc is IPremiumCalc {

    using SafeMath for uint256;

    uint8   public override constant calcType = 12;      // PREMIUM type.
    bytes32 public override constant name     = "FLAT";

    uint256 public override immutable premiumFee;

    constructor(uint256 _premiumFee) public {
        premiumFee = _premiumFee;
    }

    function getPremiumPayment(address _loan) external override view returns (uint256 total, uint256 principalOwed, uint256 interest) {
        principalOwed = ILoan(_loan).principalOwed();
        interest      = principalOwed.mul(premiumFee).div(10_000);
        total         = interest.add(principalOwed);
    }

}
