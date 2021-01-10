// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./interfaces/ILoan.sol";

contract LiquidityLocker {

    address public immutable owner;           // The Pool that owns this LiquidityLocker, for authorization purposes.
    address public immutable liquidityAsset;  // The asset which this LiquidityLocker will escrow.

    // TODO: Consider checking if the pool (owner) is a valid Pool via PoolFactory.
    constructor(address _liquidityAsset, address _owner) public {
        liquidityAsset = _liquidityAsset;
        owner          = _owner;
    }
    
    modifier isOwner() {
        require(msg.sender == owner, "LiquidityLocker:ERR_MSG_SENDER_NOT_OWNER");
        _;
    }

    /**
        @notice Transfers _amount of liquidityAsset to dst.
        @param  dst Desintation to transfer liquidityAsset to.
        @param  amt Amount of liquidityAsset to transfer.
    */
    function transfer(address dst, uint256 amt) external isOwner returns (bool) {
        require(dst != address(0), "LiquidityLocker::transfer:ERR_TO_VALUE_IS_NULL_ADDRESS");
        return IERC20(liquidityAsset).transfer(dst, amt);
    }

    
    /**
        @notice Fund a loan using available assets in this liquidity locker.
        @param  loan       The loan to fund.
        @param  debtLocker The locker that will escrow debt tokens.
        @param  amt        Amount of liquidityAsset to fund the loan for.
    */
    // TODO: Consider checking if loan is valid via LoanFactory.
    function fundLoan(address loan, address debtLocker, uint256 amt) external isOwner {
        IERC20(liquidityAsset).approve(loan, amt);
        ILoan(loan).fundLoan(amt, debtLocker);
    }
}
