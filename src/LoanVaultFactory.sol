// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "./LoanVault.sol";
import "./interface/IGlobals.sol";
import "lib/openzeppelin-contracts/src/math/SafeMath.sol";
import "./library/TokenUUID.sol";

/// @title LoanVaultFactory instantiates LoanVault contracts.
contract LoanVaultFactory {

	using SafeMath for uint256;

    // Data structures for loan vaults.
    mapping(uint256 => address) private loanVaults;
    mapping(address => bool) private _isLoanVault;
    
    /// @notice Incrementor for number of loan vaults created.
    uint256 public loanVaultsCreated;

    /// @notice The MapleGlobals.sol contract.
    address public mapleGlobals;
    
    /// @notice The FundingLockerFactory to use for this LoanVaultFactory.
    address public fundingLockerFactory;
    
    /// @notice The CollateralLockerFactory to use for this LoanVaultFactory.
    address public collateralLockerFactory;

    constructor(address _mapleGlobals, address _fundingLockerFactory, address _collateralLockerFactory) public {
        mapleGlobals = _mapleGlobals;
        fundingLockerFactory = _fundingLockerFactory;
        collateralLockerFactory = _collateralLockerFactory;
    }

    // Authorization to call Treasury functions.
    modifier isGovernor() {
        require(msg.sender == IGlobals(mapleGlobals).governor(), "LoanVaultFactory::ERR_MSG_SENDER_NOT_GOVERNOR");
        _;
    }

    /// @notice Fired when user calls createLoanVault()
    event LoanVaultCreated(
        uint256 _loanVaultID,
		address _loanVaultAddress,
        address indexed _borrower,
        address indexed _assetRequested,
        address _assetCollateral,
        uint[6] _specifications,
        bytes32[3] _calculators
    );

    /// @notice Instantiates a LoanVault
    /// @param _assetRequested The asset borrower is requesting funding in.
    /// @param _assetCollateral The asset provided as collateral by the borrower.
    /// @param _specifications The specifications of the loan.
    ///        _specifications[0] = APR_BIPS
    ///        _specifications[1] = TERM_DAYS
    ///        _specifications[2] = PAYMENT_INTERVAL_DAYS
    ///        _specifications[3] = MIN_RAISE
    ///        _specifications[4] = COLLATERAL_BIPS_RATIO
    ///        _specifications[5] = FUNDING_PERIOD_DAYS
    /// @param _calculators The calculators used for the loan.
    ///        _calculators[0] = Repayment ("Interest Structure") Calculator
    ///        _calculators[1] = LateFee Calculator
    ///        _calculators[2] = Premium Calculator
    /// @return The address of the newly instantiated LoanVault.
    function createLoanVault(
        address _assetRequested,
        address _assetCollateral,
        uint[6] memory _specifications,
        bytes32[3] memory _calculators
    ) public returns (address) {

        // Pre-checks.
        require(
            _assetCollateral!= address(0),
            "LoanVaultFactory::createLoanVault:ERR_NULL_ASSET_COLLATERAL"
        );
        require(
            IGlobals(mapleGlobals).interestStructureCalculators(_calculators[0]) != address(0),
            "LoanVaultFactory::createLoanVault:ERR_NULL_INTEREST_STRUCTURE_CALC"
        );
        require(
            IGlobals(mapleGlobals).lateFeeCalculators(_calculators[1]) != address(0),
            "LoanVaultFactory::createLoanVault:ERR_NULL_LATE_FEE_CALC"
        );
        require(
            IGlobals(mapleGlobals).premiumCalculators(_calculators[2]) != address(0),
            "LoanVaultFactory::createLoanVault:ERR_NULL_PREMIUM_CALC"
        );
        
        // Deploy loan vault contract.
	    string memory _tUUID = TokenUUID.mkUUID(loanVaultsCreated+1);

        LoanVault vault = new LoanVault(
            _assetRequested,
            _assetCollateral,
            fundingLockerFactory,
            collateralLockerFactory,
            mapleGlobals,
            _specifications,
            [
                IGlobals(mapleGlobals).interestStructureCalculators(_calculators[0]),
                IGlobals(mapleGlobals).lateFeeCalculators(_calculators[1]),
                IGlobals(mapleGlobals).premiumCalculators(_calculators[2])
            ],
	        _tUUID
        );

        // Update LoanVaultFactory identification mappings.
        loanVaults[loanVaultsCreated] = address(vault);
        _isLoanVault[address(vault)] = true;

        // Emit event.
        emit LoanVaultCreated(
            loanVaultsCreated,
            address(vault),
            msg.sender,
            _assetRequested,
            _assetCollateral,
            _specifications,
            [_calculators[0], _calculators[1], _calculators[2]]
        );

        // Increment loanVaultCreated (IDs), return loan vault address.
        loanVaultsCreated++;
        return address(vault);
    }

    /// @dev Fetch the address of a loan vault using the id (incrementor).
    /// @param _id The incrementor value to supply.
    /// @return The address of the loan vault at _id.
    function getLoanVault(uint256 _id) public view returns (address) {
        return loanVaults[_id];
    }

    /// @dev Identifies if a loan vault was created through this contract.
    /// @param _loanVault The incrementor value to supply.
    /// @return True if the address is a loan vault created through this contract.
    function isLoanVault(address _loanVault) public view returns (bool) {
        return _isLoanVault[_loanVault];
    }

    /// @dev Governor can adjust the fundingLockerFactory.
    /// @param _fundingLockerFactory The new fundingLockerFactory address.
    function setFundingLockerFactory(address _fundingLockerFactory) public isGovernor {
        fundingLockerFactory = _fundingLockerFactory;
    }
    
    /// @dev Governor can adjust the fundingLockerFactory.
    /// @param _collateralLockerFactory The new collateralLockerFactory address.
    function setCollateralLockerFactory(address _collateralLockerFactory) public isGovernor {
        collateralLockerFactory = _collateralLockerFactory;
    }
}
