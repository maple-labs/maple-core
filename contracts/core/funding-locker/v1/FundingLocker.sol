// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { SafeERC20, IERC20 } from "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/SafeERC20.sol";

import { IFundingLocker } from "./interfaces/IFundingLocker.sol";

/// @title FundingLocker holds custody of Liquidity Asset tokens during the funding period of a Loan.
contract FundingLocker is IFundingLocker {

    using SafeERC20 for IERC20;

    IERC20  public override immutable liquidityAsset;
    address public override immutable loan;

    constructor(address _liquidityAsset, address _loan) public {
        liquidityAsset = IERC20(_liquidityAsset);
        loan           = _loan;
    }

    /**
        @dev Checks that `msg.sender` is the Loan.
    */
    modifier isLoan() {
        require(msg.sender == loan, "FL:NOT_L");
        _;
    }

    function pull(address dst, uint256 amt) isLoan external override {
        liquidityAsset.safeTransfer(dst, amt);
    }

    function drain() isLoan external override {
        uint256 amt = liquidityAsset.balanceOf(address(this));
        liquidityAsset.safeTransfer(loan, amt);
    }

}
