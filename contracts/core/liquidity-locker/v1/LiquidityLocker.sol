// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { SafeERC20, IERC20 } from  "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/SafeERC20.sol";

import { ILoan } from "../../loan/v1/interfaces/ILoan.sol";

import { ILiquidityLocker } from "./interfaces/ILiquidityLocker.sol";

/// @title LiquidityLocker holds custody of Liquidity Asset tokens for a given Pool.
contract LiquidityLocker is ILiquidityLocker {

    using SafeERC20 for IERC20;

    address public override immutable pool;
    IERC20  public override immutable liquidityAsset;

    constructor(address _liquidityAsset, address _pool) public {
        liquidityAsset = IERC20(_liquidityAsset);
        pool           = _pool;
    }

    /**
        @dev Checks that `msg.sender` is the Pool.
     */
    modifier isPool() {
        require(msg.sender == pool, "LL:NOT_P");
        _;
    }

    function transfer(address dst, uint256 amt) external override isPool {
        require(dst != address(0), "LL:NULL_DST");
        liquidityAsset.safeTransfer(dst, amt);
    }

    function fundLoan(address loan, address debtLocker, uint256 amount) external override isPool {
        liquidityAsset.safeApprove(loan, amount);
        ILoan(loan).fundLoan(debtLocker, amount);
    }

}
