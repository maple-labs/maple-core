// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { Pausable } from "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";

import { IMapleGlobals } from "core/globals/v1/interfaces/IMapleGlobals.sol";

import { ILoanFactory } from "./interfaces/ILoanFactory.sol";

import { Loan } from "./Loan.sol";

/// @title LoanFactory instantiates Loans.
contract LoanFactory is ILoanFactory, Pausable {

    uint8 public override constant CL_FACTORY = 0;
    uint8 public override constant FL_FACTORY = 2;

    uint8 public override constant INTEREST_CALC_TYPE = 10;
    uint8 public override constant LATEFEE_CALC_TYPE  = 11;
    uint8 public override constant PREMIUM_CALC_TYPE  = 12;

    IMapleGlobals public override globals;

    uint256 public override loansCreated;

    mapping(uint256 => address) public override loans;
    mapping(address => bool)    public override isLoan;  // True only if a Loan was created by this factory.

    mapping(address => bool) public override loanFactoryAdmins;

    constructor(address _globals) public {
        globals = IMapleGlobals(_globals);
    }

    function setGlobals(address newGlobals) external override {
        _isValidGovernor();
        globals = IMapleGlobals(newGlobals);
    }

    function createLoan(
        address liquidityAsset,
        address collateralAsset,
        address flFactory,
        address clFactory,
        uint256[5] memory specs,
        address[3] memory calcs
    ) external override whenNotPaused returns (address loanAddress) {
        _whenProtocolNotPaused();
        IMapleGlobals _globals = globals;

        // Perform validity checks.
        require(_globals.isValidSubFactory(address(this), flFactory, FL_FACTORY), "LF:INVALID_FLF");
        require(_globals.isValidSubFactory(address(this), clFactory, CL_FACTORY), "LF:INVALID_CLF");

        require(_globals.isValidCalc(calcs[0], INTEREST_CALC_TYPE), "LF:INVALID_INT_C");
        require(_globals.isValidCalc(calcs[1],  LATEFEE_CALC_TYPE), "LF:INVALID_LATE_FEE_C");
        require(_globals.isValidCalc(calcs[2],  PREMIUM_CALC_TYPE), "LF:INVALID_PREM_C");

        // Deploy new Loan.
        Loan loan = new Loan(
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

    function setLoanFactoryAdmin(address loanFactoryAdmin, bool allowed) external override {
        _isValidGovernor();
        loanFactoryAdmins[loanFactoryAdmin] = allowed;
        emit LoanFactoryAdminSet(loanFactoryAdmin, allowed);
    }

    function pause() external override {
        _isValidGovernorOrLoanFactoryAdmin();
        super._pause();
    }

    function unpause() external override {
        _isValidGovernorOrLoanFactoryAdmin();
        super._unpause();
    }

    /**
        @dev Checks that `msg.sender` is the Governor.
     */
    function _isValidGovernor() internal view {
        require(msg.sender == globals.governor(), "LF:NOT_GOV");
    }

    /**
        @dev Checks that `msg.sender` is the Governor or a LoanFactory Admin.
     */
    function _isValidGovernorOrLoanFactoryAdmin() internal view {
        require(msg.sender == globals.governor() || loanFactoryAdmins[msg.sender], "LF:NOT_GOV_OR_ADMIN");
    }

    /**
        @dev Checks that the protocol is not in a paused state.
     */
    function _whenProtocolNotPaused() internal view {
        require(!globals.protocolPaused(), "LF:PROTO_PAUSED");
    }

}
