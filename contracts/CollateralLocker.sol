// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title CollateralLocker holds custody of collateralAsset for Loans.
contract CollateralLocker {

    IERC20 public immutable collateralAsset;  // Address the loan is funded with
    address public immutable loan;            // Loan this CollateralLocker is attached to

    constructor(address _collateralAsset, address _loan) public {
        collateralAsset = IERC20(_collateralAsset);
        loan            = _loan;
    }

    modifier isLoan() {
        require(msg.sender == loan, "CollateralLocker:MSG_SENDER_NOT_LOAN");
        _;
    }

    /**
        @dev Transfers amt of collateralAsset to dst. Only Loan can call this function.
        @param dst Desintation to transfer collateralAsset to
        @param amt Amount of collateralAsset to transfer
    */
    function pull(address dst, uint256 amt) isLoan public returns(bool) {
        return collateralAsset.transfer(dst, amt);
    }
}
