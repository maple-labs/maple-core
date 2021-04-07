// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "./interfaces/ILoan.sol";

import "lib/openzeppelin-contracts/contracts/token/ERC20/SafeERC20.sol";

/// @title LiquidityLocker holds custody of liquidityAsset tokens for a given Pool.
contract LiquidityLocker {

    using SafeERC20 for IERC20;

    address public immutable pool;            // The Pool that owns this LiquidityLocker, for authorization purposes
    IERC20  public immutable liquidityAsset;  // The asset which this LiquidityLocker will escrow

    constructor(address _liquidityAsset, address _pool) public {
        liquidityAsset = IERC20(_liquidityAsset);
        pool           = _pool;
    }
    
    modifier isPool() {
        require(msg.sender == pool, "LiquidityLocker:MSG_SENDER_NOT_POOL");
        _;
    }

    /**
        @dev Transfers amt of liquidityAsset to dst. Only the Pool can call this function.
        @param dst Desintation to transfer liquidityAsset to
        @param amt Amount of liquidityAsset to transfer
    */
    function transfer(address dst, uint256 amt) external isPool {
        require(dst != address(0), "LiquidityLocker:NULL_TRASNFER_DST");
        liquidityAsset.safeTransfer(dst, amt);
    }

    /**
        @dev Fund a loan using available assets in this liquidity locker. Only the Pool can call this function.
        @param  loan       The loan to fund
        @param  debtLocker The locker that will escrow debt tokens
        @param  amt        Amount of liquidityAsset to fund the loan for
    */
    function fundLoan(address loan, address debtLocker, uint256 amt) external isPool {
        liquidityAsset.safeApprove(loan, amt);
        ILoan(loan).fundLoan(debtLocker, amt);
    }
}
