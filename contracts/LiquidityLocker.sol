// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./interfaces/ILoan.sol";

contract LiquidityLocker {

    address public immutable owner;           // The Pool that owns this LiquidityLocker, for authorization purposes.
    address public           liquidityAsset;  // The asset which this LiquidityLocker will escrow.

    // TODO: Consider checking if the pool (owner) is a valid Pool via PoolFactory.
    constructor(address _liquidityAsset, address pool) public {
        liquidityAsset = _liquidityAsset;
        owner          = pool;
    }
    
    modifier isOwner() {
        require(msg.sender == owner, "LiquidityLocker:ERR_MSG_SENDER_NOT_OWNER");
        _;
    }

    /// @notice Transfer liquidityAsset from this contract to an external contract.
    /// @param amt Amount to transfer liquidityAsset to.
    /// @param dst Address to send liquidityAsset to.
    /// @return true if transfer succeeds.
    function transfer(address dst, uint256 amt) external isOwner returns (bool) {
        require(dst != address(0), "LiquidityLocker::transfer:ERR_TO_VALUE_IS_NULL_ADDRESS");
        return IERC20(liquidityAsset).transfer(dst, amt);
    }

    // TODO: Consider checking if loan is valid via LoanFactory.
    /// @notice Fund a particular loan using available LiquidityAsset.
    /// @param loan The address of the Loan to fund.
    /// @param amt The amount of LiquidityAsset to fund.
    function fundLoan(address loan, address debtLocker, uint256 amt) external isOwner {
        IERC20(liquidityAsset).approve(loan, amt);
        ILoan(loan).fundLoan(amt, debtLocker);
    }
}
