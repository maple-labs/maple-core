// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/SafeERC20.sol";

/// @title FundingLocker holds custody of Liquidity Asset tokens during the funding period of a Loan.
contract FundingLocker {

    using SafeERC20 for IERC20;

    IERC20  public immutable liquidityAsset;
    address public immutable loan;

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

    function pull(address destination, uint256 amount) isLoan external {
        liquidityAsset.safeTransfer(destination, amount);
    }

    function drain() isLoan external {
        uint256 amt = liquidityAsset.balanceOf(address(this));
        liquidityAsset.safeTransfer(loan, amt);
    }

}
