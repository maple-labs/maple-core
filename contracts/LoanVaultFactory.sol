pragma solidity 0.7.0;

import "./LoanVault.sol";

/// @title LoanVaultFactory instantiates LoanVault contracts.
contract LoanVaultFactory {

    // Data structures for loan vaults.
    mapping(uint256 => address) private loanVaults;
    mapping(address => bool) private _isLoanVault;
    
    /// @notice Incrementor for number of loan vaults created.
    uint256 public loanVaultsCreated;

    /// @notice The MapleGlobals.sol contract.
    address public mapleGlobals;

    constructor(address _mapleGlobals) {
        mapleGlobals = _mapleGlobals;
    }

    /// @notice Instantiates a loan vault.
    /// @param _assetRequested The asset borrower is requesting funding in.
    /// @param _assetCollateral The asset provided as collateral by the borrower.
    /// @param _fundingLockerFactory Factory to instantiate FundingLocker through.
    /// @param _collateralLockerFactory Factory to instantiate CollateralLocker through.
    /// @param name The name of the loan vault's token (minted when investors fund the loan).
    /// @param symbol The ticker of the loan vault's token.
    /// @param _specifications The specifications of the loan.
    ///        _specifications[0] = APR_BIPS
    ///        _specifications[1] = NUMBER_OF_PAYMENTS
    ///        _specifications[2] = PAYMENT_INTERVAL_SECONDS
    ///        _specifications[3] = MIN_RAISE
    ///        _specifications[4] = DESIRED_RAISE
    ///        _specifications[5] = COLLATERAL_AT_DESIRED_RAISE
    ///        _specifications[6] = FUNDING_PERIOD_SECONDS
    /// @param _repaymentCalculator The calculator used for interest and principal repayment calculations.
    /// @param _premiumCalculator The calculator used for call premiums.
    /// @return The address of the newly instantiated liquidity pool.
    function createLoanVault(
        address _assetRequested,
        address _assetCollateral,
        address _fundingLockerFactory,
        address _collateralLockerFactory,
        string memory name,
        string memory symbol,
        uint[7] memory _specifications,
        address _repaymentCalculator,
        address _premiumCalculator
    ) public returns (address) {
        LoanVault vault = new LoanVault(
            _assetRequested,
            _assetCollateral,
            _fundingLockerFactory,
            _collateralLockerFactory,
            name,
            symbol,
            mapleGlobals,
            _specifications,
            _repaymentCalculator,
            _premiumCalculator
        );
        loanVaults[loanVaultsCreated] = address(vault);
        _isLoanVault[address(vault)] = true;
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
}
