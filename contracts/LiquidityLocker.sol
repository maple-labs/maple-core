// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./interfaces/ILoan.sol";

/// @title LiquidityLocker holds custody of Liquidity Asset tokens for a given Pool.
contract LiquidityLocker {

    using SafeERC20 for IERC20;

    address public immutable pool;            // The Pool that owns this LiquidityLocker.
    IERC20  public immutable liquidityAsset;  // The Liquidity Asset which this LiquidityLocker will escrow.

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

    /**
        @dev   Transfers amount of Liquidity Asset to a destination account. Only the Pool can call this function.
        @param dst Destination to transfer Liquidity Asset to.
        @param amt Amount of Liquidity Asset to transfer.
    */
    function transfer(address dst, uint256 amt) external isPool {
        require(dst != address(0), "LL:NULL_DST");
        liquidityAsset.safeTransfer(dst, amt);
    }

    /**
        @dev   Funds a Loan using available assets in this LiquidityLocker. Only the Pool can call this function.
        @param loan       The Loan to fund.
        @param debtLocker The DebtLocker that will escrow debt tokens.
        @param amt        Amount of Liquidity Asset to fund the Loan for.
    */
    function fundLoan(address loan, address debtLocker, uint256 amt) external isPool {
        liquidityAsset.safeApprove(loan, amt);
        ILoan(loan).fundLoan(debtLocker, amt);
    }

}
