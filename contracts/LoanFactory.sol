// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "@openzeppelin/contracts/utils/Pausable.sol";

import "./Loan.sol";

/// @title LoanFactory instantiates Loans.
contract LoanFactory is Pausable {

    using SafeMath for uint256;

    uint8 public constant CL_FACTORY = 0;  // Factory type of `CollateralLockerFactory`.
    uint8 public constant FL_FACTORY = 2;  // Factory type of `FundingLockerFactory`.

    uint8 public constant INTEREST_CALC_TYPE = 10;  // Calc type of `RepaymentCalc`.
    uint8 public constant LATEFEE_CALC_TYPE  = 11;  // Calc type of `LateFeeCalc`.
    uint8 public constant PREMIUM_CALC_TYPE  = 12;  // Calc type of `PremiumCalc`.

    IMapleGlobals public globals;  // Instance of the MapleGlobals.

    uint256 public loansCreated;   // Incrementor for number of Loans created.

    mapping(uint256 => address) public loans;   // Loans address mapping.
    mapping(address => bool)    public isLoan;  // True only if a Loan was created by this factory.

    mapping(address => bool) public loanFactoryAdmins;  // The LoanFactory Admin addresses that have permission to do certain operations in case of disaster management.

    event LoanFactoryAdminSet(address indexed loanFactoryAdmin, bool allowed);

    event LoanCreated(
        address loan,
        address indexed borrower,
        address indexed liquidityAsset,
        address collateralAsset,
        address collateralLocker,
        address fundingLocker,
        uint256[5] specs,
        address[3] calcs,
        string name,
        string symbol
    );

    constructor(address _globals) public {
        globals = IMapleGlobals(_globals);
    }

    /**
        @dev   Sets MapleGlobals. Only the Governor can call this function.
        @param newGlobals Address of new MapleGlobals.
    */
    function setGlobals(address newGlobals) external {
        _isValidGovernor();
        globals = IMapleGlobals(newGlobals);
    }

    /**
        @dev    Create a new Loan.
        @dev    It emits a `LoanCreated` event.
        @param  liquidityAsset  Asset the Loan will raise funding in.
        @param  collateralAsset Asset the Loan will use as collateral.
        @param  flFactory       The factory to instantiate a FundingLocker from.
        @param  clFactory       The factory to instantiate a CollateralLocker from.
        @param  specs           Contains specifications for this Loan.
                                    specs[0] = apr
                                    specs[1] = termDays
                                    specs[2] = paymentIntervalDays
                                    specs[3] = requestAmount
                                    specs[4] = collateralRatio
        @param  calcs           The calculators used for this Loan.
                                    calcs[0] = repaymentCalc
                                    calcs[1] = lateFeeCalc
                                    calcs[2] = premiumCalc
        @return loanAddress     Address of the instantiated Loan.
    */
    function createLoan(
        address liquidityAsset,
        address collateralAsset,
        address flFactory,
        address clFactory,
        uint256[5] memory specs,
        address[3] memory calcs
    ) external whenNotPaused returns (address loanAddress) {
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

    /**
        @dev   Sets a LoanFactory Admin. Only the Governor can call this function.
        @dev   It emits a `LoanFactoryAdminSet` event.
        @param loanFactoryAdmin An address being allowed or disallowed as a LoanFactory Admin.
        @param allowed          Status of a LoanFactory Admin.
    */
    function setLoanFactoryAdmin(address loanFactoryAdmin, bool allowed) external {
        _isValidGovernor();
        loanFactoryAdmins[loanFactoryAdmin] = allowed;
        emit LoanFactoryAdminSet(loanFactoryAdmin, allowed);
    }

    /**
        @dev Triggers paused state. Halts functionality for certain functions. Only the Governor or a LoanFactory Admin can call this function.
    */
    function pause() external {
        _isValidGovernorOrLoanFactoryAdmin();
        super._pause();
    }

    /**
        @dev Triggers unpaused state. Restores functionality for certain functions. Only the Governor or a LoanFactory Admin can call this function.
    */
    function unpause() external {
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
