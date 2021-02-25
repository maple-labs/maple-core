// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./interfaces/ILoan.sol";

contract LiquidityLocker {

    address public immutable owner;           // The Pool that owns this LiquidityLocker, for authorization purposes.
    IERC20  public immutable liquidityAsset;  // The asset which this LiquidityLocker will escrow.

    constructor(address _liquidityAsset, address _owner) public {
        liquidityAsset = IERC20(_liquidityAsset);
        owner          = _owner;
    }
    
    modifier isOwner() {
        require(msg.sender == owner, "LiquidityLocker:MSG_SENDER_NOT_OWNER");
        _;
    }

    /**
        @dev Transfers amt of liquidityAsset to dst.
        @param  dst Desintation to transfer liquidityAsset to.
        @param  amt Amount of liquidityAsset to transfer.
    */
    function transfer(address dst, uint256 amt) external isOwner returns (bool) {
        require(dst != address(0), "LiquidityLocker:NULL_TRASNFER_DST");
        return liquidityAsset.transfer(dst, amt);
    }

    /**
        @dev Fund a loan using available assets in this liquidity locker.
        @param  loan       The loan to fund.
        @param  debtLocker The locker that will escrow debt tokens.
        @param  amt        Amount of liquidityAsset to fund the loan for.
    */
    function fundLoan(address loan, address debtLocker, uint256 amt) external isOwner {
        liquidityAsset.approve(loan, amt);
        ILoan(loan).fundLoan(debtLocker, amt);
    }
}
