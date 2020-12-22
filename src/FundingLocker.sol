// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "lib/openzeppelin-contracts/src/token/ERC20/IERC20.sol";

contract FundingLocker {

    /// @notice Address the loan is funded with.
    address public immutable fundingAsset;

    /// @notice LoanVault this FundingLocker is attached to.
    address public immutable loanVault;

    constructor(address _fundingAsset, address _loanVault) public {
        fundingAsset = _fundingAsset;
        loanVault = _loanVault;
    }

    modifier isLoanVault() {
        require(msg.sender == loanVault, "FundingLocker::ERR_ISLOANVAULT_CHECK");
        _;
    }

    /// @notice Transfers _amount of fundingAsset to _destination.
    /// @param _destination Desintation to transfer fundingAsset to.
    /// @param _amount Amount of fundingAsset to transfer.
    function pull(address _destination, uint256 _amount) isLoanVault public returns(bool) {
        return IERC20(fundingAsset).transfer(_destination, _amount);
    }

    /// @notice Transfers the remainder of fundingAsset to LoanVault;
    function drain() isLoanVault public returns(bool) {
        uint256 transferAmount = IERC20(fundingAsset).balanceOf(address(this));
        return IERC20(fundingAsset).transfer(loanVault, transferAmount);
    }
    
}
