// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/SafeERC20.sol";

/// @title CollateralLocker holds custody of collateralAsset for Loans.
contract CollateralLocker {

    using SafeERC20 for IERC20;

    IERC20  public immutable collateralAsset;  // Address the loan is funded with
    address public immutable loan;             // Loan contract address this CollateralLocker is attached to

    constructor(address _collateralAsset, address _loan) public {
        collateralAsset = IERC20(_collateralAsset);
        loan            = _loan;
    }

    /**
        @dev Checks that msg.sender is the Loan.
    */
    modifier isLoan() {
        require(msg.sender == loan, "CL:NOT_LOAN");
        _;
    }

    /**
        @dev Transfers amt of collateralAsset to dst. Only the Loan can call this function.
        @param dst Desintation to transfer collateralAsset to
        @param amt Amount of collateralAsset to transfer
    */
    function pull(address dst, uint256 amt) isLoan external {
        collateralAsset.safeTransfer(dst, amt);
    }
}
