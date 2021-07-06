// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "./LoanV2.sol";
import "core/loan/v1/LoanFactory.sol";

/// @title LoanFactoryV2 instantiates Loans.
contract LoanFactoryV2 is LoanFactory {

    constructor(address _globals) LoanFactory(_globals) public {}

    function createLoan(
        address liquidityAsset,
        address collateralAsset,
        address flFactory,
        address clFactory,
        uint256[5] memory specs,
        address[3] memory calcs
    ) external override whenNotPaused returns (address loanAddress) {
        _whenProtocolNotPaused();

        // Perform validity checks.
        _preParamValidation(flFactory, clFactory, calcs);

        // Deploy new Loan.
        LoanV2 loan = new LoanV2(
            msg.sender,
            liquidityAsset,
            collateralAsset,
            flFactory,
            clFactory,
            specs,
            calcs
        );

        // Update the LoanFactory identification mappings.
        loanAddress         = address(loan);
        loans[loansCreated] = loanAddress;
        isLoan[loanAddress] = true;
        ++loansCreated;

        emit LoanCreated(
            loanAddress,
            msg.sender,
            liquidityAsset,
            collateralAsset,
            loan.collateralLocker(),
            loan.fundingLocker(),
            specs,
            calcs,
            loan.name(),
            loan.symbol()
        );
    }

}