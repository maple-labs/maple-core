// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

import "./BasicFDT.sol";

/// @title FDT inherits BasicFDT and uses the original ERC-2222 logic. 
abstract contract FDT is BasicFDT {
    using SafeMath       for uint256;
    using SafeMathUint   for uint256;
    using SignedSafeMath for  int256;
    using SafeMathInt    for  int256;

    IERC20 public fundsToken;  // The fundsToken (dividends)

    uint256 public fundsTokenBalance;  // The amount of fundsToken (loanAsset) currently present and accounted for in this contract.

    constructor(string memory name, string memory symbol, address _fundsToken) BasicFDT(name, symbol) public {
        fundsToken = IERC20(_fundsToken);
    }

    /**
        @dev Withdraws all available funds for a token holder
    */
    function withdrawFunds() public virtual override {
        uint256 withdrawableFunds = _prepareWithdraw();

        require(fundsToken.transfer(msg.sender, withdrawableFunds), "FDT:TRANSFER_FAILED");

        _updateFundsTokenBalance();
    }

    /**
        @dev Updates the current funds token balance
        and returns the difference of new and previous funds token balances
        @return A int256 representing the difference of the new and previous funds token balance
    */
    function _updateFundsTokenBalance() internal virtual override returns (int256) {
        uint256 _prevFundsTokenBalance = fundsTokenBalance;

        fundsTokenBalance = fundsToken.balanceOf(address(this));

        return int256(fundsTokenBalance).sub(int256(_prevFundsTokenBalance));
    }
}
