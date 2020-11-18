pragma solidity 0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LoanVaultFundingLocker {

    /// @notice Address the loan is funded with.
    address public immutable fundingAsset;

    /// @notice LoanVault this FundingLocker is attached to.
    address public immutable loanVault;

    constructor(address _fundingAsset, address _loanVault) {
        fundingAsset = _fundingAsset;
        loanVault = _loanVault;
    }

    modifier isLoanVault() {
        require(msg.sender == loanVault, "LoanVaultFundingLocker::ERR_ISLOANVAULT_CHECK");
        _;
    }
    
}
