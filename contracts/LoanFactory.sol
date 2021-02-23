// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "./Loan.sol";

import "./library/TokenUUID.sol";

import "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";

/// @title LoanFactory instantiates Loan contracts.
contract LoanFactory is Pausable {

    using SafeMath for uint256;

    uint8 public constant COLLATERAL_LOCKER_FACTORY  = 0;   // Factory type of `CollateralLockerFactory`.
    uint8 public constant FUNDING_LOCKER_FACTORY     = 2;   // Factory type of `FundingLockerFactory`.
    uint8 public constant INTEREST_CALC_TYPE         = 10;  // Calc type of `RepaymentCalc`.
    uint8 public constant LATEFEE_CALC_TYPE          = 11;  // Calc type of `LateFeeCalc`.
    uint8 public constant PREMIUM_CALC_TYPE          = 12;  // Calc type of `PremiumCalc`.

    IGlobals public globals;  // The MapleGlobals.sol contract.

    uint256 public loansCreated;  // Incrementor for number of loan vaults created.

    mapping(uint256 => address) public loans;
    mapping(address => bool)    public isLoan;

    event LoanCreated(
        string  indexed tUUID,
        address loan,
        address indexed borrower,
        address indexed loanAsset,
        address collateralAsset,
        address collateralLocker,
        address fundingLocker,
        uint256[6] specs,
        address[3] calcs,
        string name,
        string symbol
    );
    
    constructor(address _globals) public {
        globals = IGlobals(_globals);
    }

    /**
        @dev Update the maple globals contract
        @param  newGlobals Address of new maple globals contract
    */
    function setGlobals(address newGlobals) external {
        _isValidGovernor();
        globals = IGlobals(newGlobals);
    }

    /**
        @dev Create a new Loan.
        @param  loanAsset       Asset the loan will raise funding in.
        @param  collateralAsset Asset the loan will use as collateral.
        @param  flFactory       The factory to instantiate a Funding Locker from.
        @param  clFactory       The factory to instantiate a Collateral Locker from.
        @param  specs           Contains specifications for this loan.
                specs[0] = apr
                specs[1] = termDays
                specs[2] = paymentIntervalDays
                specs[3] = requestAmount
                specs[4] = collateralRatio
                specs[5] = fundingPeriodDays
        @param  calcs           The calculators used for the loan.
                calcs[0] = repaymentCalc
                calcs[1] = lateFeeCalc
                calcs[2] = premiumCalc
        @return Address of the instantiated Loan.
    */
    function createLoan(
        address loanAsset,
        address collateralAsset,
        address flFactory,
        address clFactory,
        uint256[6] memory specs,
        address[3] memory calcs
    ) external whenNotPaused returns (address) {
        _whenProtocolNotPaused();
        IGlobals _globals = globals;

        require(_globals.isValidSubFactory(address(this), flFactory, FUNDING_LOCKER_FACTORY),    "LF:INVALID_FL_FACTORY");
        require(_globals.isValidSubFactory(address(this), clFactory, COLLATERAL_LOCKER_FACTORY), "LF:INVALID_CL_FACTORY");

        require(_globals.isValidCalc(calcs[0], INTEREST_CALC_TYPE), "LF:INVALID_INTEREST_CALC");
        require(_globals.isValidCalc(calcs[1],  LATEFEE_CALC_TYPE), "LF:INVALID_LATE_FEE_CALC");
        require(_globals.isValidCalc(calcs[2],  PREMIUM_CALC_TYPE), "LF:INVALID_PREMIUM_CALC");
        
        // Deploy loan vault contract.
	    string memory tUUID = TokenUUID.generateUUID(loansCreated + 1);

        Loan loan = new Loan(
            msg.sender,
            loanAsset,
            collateralAsset,
            flFactory,
            clFactory,
            specs,
            calcs,
            tUUID
        );

        // Update LoanFactory identification mappings.
        loans[loansCreated]   = address(loan);
        isLoan[address(loan)] = true;

        // Emit event.
        emit LoanCreated(
            tUUID,
            address(loan),
            msg.sender,
            loanAsset,
            collateralAsset,
            loan.collateralLocker(),
            loan.fundingLocker(),
            specs,
            calcs,
            loan.name(),
            loan.symbol()
        );

        // Increment loanVaultCreated (IDs), return loan address.
        loansCreated++;
        return address(loan);
    }

    /**
        @dev Triggers stopped state.
             The contract must not be paused.
    */
    function pause() external { 
        _isValidGovernor();
        super._pause();
    }

    /**
        @dev Returns to normal state.
             The contract must be paused.
    */
    function unpause() external {
        _isValidGovernor();
        super._unpause();
    }

    function _isValidGovernor() internal view {
        require(msg.sender == globals.governor(), "LF:INVALID_GOVERNOR");
    }
<<<<<<< HEAD

    function _whenProtocolNotPaused() internal {
        require(!globals.protocolPaused(), "LF:PROTOCOL_PAUSED");
    }
=======
>>>>>>> initial switches
    
}
