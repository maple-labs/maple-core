// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/SafeERC20.sol";

/// @title FundingLocker holds custody of Liquidity Asset tokens during the funding period of a Loan.
contract FundingLocker {

    using SafeERC20 for IERC20;

    IERC20  public immutable liquidityAsset;  // Asset the Loan was funded with.
    address public immutable loan;            // Loan this FundingLocker has funded.

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

    /**
        @dev   Transfers amount of Liquidity Asset to a destination account. Only the Loan can call this function.
        @param dst Destination to transfer Liquidity Asset to.
        @param amt Amount of Liquidity Asset to transfer.
    */
    function pull(address dst, uint256 amt) isLoan external {
        liquidityAsset.safeTransfer(dst, amt);
    }

    /**
        @dev Transfers entire amount of Liquidity Asset held in escrow to the Loan. Only the Loan can call this function.
    */
    function drain() isLoan external {
        uint256 amt = liquidityAsset.balanceOf(address(this));
        liquidityAsset.safeTransfer(loan, amt);
    }

}
