// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

import "./ExtendedFDT.sol";

abstract contract StakeLockerFDT is ExtendedFDT {
    using SafeMath       for uint256;
    using SafeMathUint   for uint256;
    using SignedSafeMath for  int256;
    using SafeMathInt    for  int256;

    IERC20 public immutable fundsToken;

    uint256 public bptLosses;          // Sum of all unrecognized losses 
    uint256 public lossesBalance;      // The amount of losses present and accounted for in this contract.
    uint256 public fundsTokenBalance;  // The amount of fundsToken (loanAsset) currently present and accounted for in this contract.

    constructor(string memory name, string memory symbol, address _fundsToken) ExtendedFDT(name, symbol) public {
        fundsToken = IERC20(_fundsToken);
    }

    /**
        @dev Updates loss accounting for msg.sender, recognizing losses
        @return losses - amount to be subtracted from given withdraw amount
    */
    function recognizeLosses() internal override returns (uint256 losses) {
        losses = _prepareLossesWithdraw();

        bptLosses = bptLosses.sub(losses);

        _updateLossesBalance();
    }

    /**
        @dev Updates the current funds token balance and returns the difference of new and previous funds token balances.
        @return A int256 representing the difference of the new and previous funds token balance.
    */
    function _updateLossesBalance() internal override returns (int256) {
        uint256 _prevLossesTokenBalance = lossesBalance;

        lossesBalance = bptLosses;

        return int256(lossesBalance).sub(int256(_prevLossesTokenBalance));
    }

    /**
     * @dev Updates the current funds token balance
     * and returns the difference of new and previous funds token balances
     * @return A int256 representing the difference of the new and previous funds token balance
     */
    function _updateFundsTokenBalance() internal virtual override returns (int256) {
        uint256 _prevFundsTokenBalance = fundsTokenBalance;

        fundsTokenBalance = fundsToken.balanceOf(address(this));

        return int256(fundsTokenBalance).sub(int256(_prevFundsTokenBalance));
    }

}
