// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/SafeERC20.sol";

import "./ExtendedFDT.sol";
import "./ERC2258.sol";

/// @title StakeLockerFDT inherits ExtendedFDT and accounts for gains/losses for Stakers.
abstract contract StakeLockerFDT is ExtendedFDT, ERC2258 {
    
    using SafeMath       for uint256;
    using SafeMathUint   for uint256;
    using SignedSafeMath for  int256;
    using SafeMathInt    for  int256;
    using SafeERC20      for  IERC20;

    IERC20 public immutable fundsToken;

    uint256 public lossesSum;      // Sum of all unrecognized losses
    uint256 public lossesBalance;  // The amount of losses present and accounted for in this contract.

    uint256 public fundsTokenBalance;  // The amount of fundsToken (liquidityAsset) currently present and accounted for in this contract.

    constructor(string memory name, string memory symbol, address _fundsToken) ExtendedFDT(name, symbol) public {
        fundsToken = IERC20(_fundsToken);
    }

    /**
        @dev   {ExtendedFDT-_burn}.
    */
    function _burn(address account, uint256 value) internal virtual override(ExtendedFDT, ERC20) {
        super._burn(account, value);
    }

    /**
        @dev   {ExtendedFDT-_mint}.
    */
    function _mint(address account, uint256 value) internal virtual override(ExtendedFDT, ERC20) {
        super._mint(account, value);
    }

    /**
        @dev   {ExtendedFDT-_transfer}.
    */
    function _transfer(address from, address to, uint256 value) internal virtual override(ExtendedFDT, ERC20) {
        super._transfer(from, to, value);
    }

    /**
        @dev    Updates loss accounting for msg.sender, recognizing losses.
        @return losses Amount to be subtracted from given withdraw amount.
    */
    function _recognizeLosses() internal override returns (uint256 losses) {
        losses = _prepareLossesWithdraw();

        lossesSum = lossesSum.sub(losses);

        _updateLossesBalance();
    }

    /**
        @dev    Updates the current losses balance and returns the difference of new and previous losses balances.
        @return A int256 representing the difference of the new and previous losses balance.
    */
    function _updateLossesBalance() internal override returns (int256) {
        uint256 _prevLossesTokenBalance = lossesBalance;

        lossesBalance = lossesSum;

        return int256(lossesBalance).sub(int256(_prevLossesTokenBalance));
    }

    /**
        @dev Withdraws all available funds for a token holder.
    */
    function withdrawFunds() public virtual override {
        uint256 withdrawableFunds = _prepareWithdraw();

        if (withdrawableFunds == uint256(0)) return;

        fundsToken.safeTransfer(msg.sender, withdrawableFunds);

        _updateFundsTokenBalance();
    }

    /**
        @dev    Updates the current interest balance and returns the difference of new and previous interest balances.
        @return A int256 representing the difference of the new and previous interest balance.
    */
    function _updateFundsTokenBalance() internal virtual override returns (int256) {
        uint256 _prevFundsTokenBalance = fundsTokenBalance;

        fundsTokenBalance = fundsToken.balanceOf(address(this));

        return int256(fundsTokenBalance).sub(int256(_prevFundsTokenBalance));
    }
}
