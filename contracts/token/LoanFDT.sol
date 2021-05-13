// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "openzeppelin-contracts/token/ERC20/SafeERC20.sol";

import "./BasicFDT.sol";

/// @title LoanFDT inherits BasicFDT and uses the original ERC-2222 logic.
abstract contract LoanFDT is BasicFDT {
    using SafeMath       for uint256;
    using SafeMathUint   for uint256;
    using SignedSafeMath for  int256;
    using SafeMathInt    for  int256;
    using SafeERC20      for  IERC20;

    IERC20 public immutable fundsToken; // The `fundsToken` (dividends).

    uint256 public fundsTokenBalance;   // The amount of `fundsToken` (Liquidity Asset) currently present and accounted for in this contract.

    constructor(string memory name, string memory symbol, address _fundsToken) BasicFDT(name, symbol) public {
        fundsToken = IERC20(_fundsToken);
    }

    /**
        @dev Withdraws all available funds for a token holder.
    */
    function withdrawFunds() public virtual override {
        uint256 withdrawableFunds = _prepareWithdraw();

        if (withdrawableFunds > uint256(0)) {
            fundsToken.safeTransfer(msg.sender, withdrawableFunds);

            _updateFundsTokenBalance();
        }
    }

    /**
        @dev    Updates the current `fundsToken` balance and returns the difference of the new and previous `fundsToken` balance.
        @return A int256 representing the difference of the new and previous `fundsToken` balance.
    */
    function _updateFundsTokenBalance() internal virtual override returns (int256) {
        uint256 _prevFundsTokenBalance = fundsTokenBalance;

        fundsTokenBalance = fundsToken.balanceOf(address(this));

        return int256(fundsTokenBalance).sub(int256(_prevFundsTokenBalance));
    }
}
