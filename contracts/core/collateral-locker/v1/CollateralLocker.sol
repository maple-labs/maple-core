// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { SafeERC20, IERC20 } from "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/SafeERC20.sol";

import { ICollateralLocker } from "./interfaces/ICollateralLocker.sol";

/// @title CollateralLocker holds custody of Collateral Asset for Loans.
contract CollateralLocker is ICollateralLocker {

    using SafeERC20 for IERC20;

    IERC20  public override immutable collateralAsset;
    address public override immutable loan;

    constructor(address _collateralAsset, address _loan) public {
        collateralAsset = IERC20(_collateralAsset);
        loan            = _loan;
    }

    /**
        @dev Checks that `msg.sender` is the Loan.
     */
    modifier isLoan() {
        require(msg.sender == loan, "CL:NOT_L");
        _;
    }

    function pull(address dst, uint256 amt) external override isLoan {
        collateralAsset.safeTransfer(dst, amt);
    }

}
