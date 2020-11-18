pragma solidity 0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LoanVaultCollateralLocker {

    /// @notice Address the loan is funded with.
    address public immutable collateralAsset;

    /// @notice LoanVault this CollateralLocker is attached to.
    address public immutable loanVault;

    constructor(address _collateralAsset, address _loanVault) {
        collateralAsset = _collateralAsset;
        loanVault = _loanVault;
    }

    modifier isLoanVault() {
        require(msg.sender == loanVault, "LoanVaultCollateralLocker::ERR_ISLOANVAULT_CHECK");
        _;
    }
    
}
