pragma solidity 0.7.0;

import "./LoanVault.sol";

/// @title LoanVaultFactory instantiates LoanVault contracts.
contract LoanVaultFactory {

    // Data structures for loan vaults.
    mapping(uint256 => address) private loanVaults;
    mapping(address => bool) private _isLoanVault;
    
    /// @notice Incrementor for number of loan vaults created.
    uint256 public loanVaultsCreated;

    /// @notice Instantiates a loan vault.
    /// @param _assetRequested The asset borrower is requesting funding in.
    /// @param _assetCollateral The asset provided as collateral by the borrower.
    /// @param name The name of the loan vault's token (minted when investors fund the loan).
    /// @param symbol The ticker of the loan vault's token.
    /// @param _mapleGlobals Address of the MapleGlobals.sol contract.
    /// @return The address of the newly instantiated liquidity pool.
    function createLoanVault(
        address _assetRequested,
        address _assetCollateral,
        string memory name,
        string memory symbol,
        address _mapleGlobals
    ) public returns (address) {
        LoanVault vault = new LoanVault(
            _assetRequested,
            _assetCollateral,
            name,
            symbol,
            _mapleGlobals
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
