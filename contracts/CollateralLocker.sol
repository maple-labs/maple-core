// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract CollateralLocker {

    /// @notice Address the loan is funded with.
    address public immutable collateralAsset;

    /// @notice LoanVault this CollateralLocker is attached to.
    address public immutable loanVault;

    constructor(address _collateralAsset, address _loanVault) public {
        collateralAsset = _collateralAsset;
        loanVault = _loanVault;
    }

    modifier isLoanVault() {
        require(msg.sender == loanVault, "CollateralLocker::ERR_ISLOANVAULT_CHECK");
        _;
    }

    /// @notice Transfers _amount of collateralAsset to _destination.
    /// @param _destination Desintation to transfer fundingAsset to.
    /// @param _amount Amount of fundingAsset to transfer.
    function pull(address _destination, uint256 _amount) isLoanVault public returns(bool) {
        return IERC20(collateralAsset).transfer(_destination, _amount);
    }
    
}
