// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { IERC20 } from "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/SafeERC20.sol";

import { ExtendedFDT, SafeMath, SafeMathInt, SafeMathUint, SignedSafeMath } from "../../funds-distribution-token/v1/ExtendedFDT.sol";

import { IStakeLockerFDT } from "./interfaces/IStakeLockerFDT.sol";

/// @title StakeLockerFDT inherits ExtendedFDT and accounts for gains/losses for Stakers.
abstract contract StakeLockerFDT is IStakeLockerFDT, ExtendedFDT {

    using SafeMath       for uint256;
    using SignedSafeMath for  int256;

    IERC20 public override immutable fundsToken;

    uint256 public override bptLosses;
    uint256 public override lossesBalance;
    uint256 public override fundsTokenBalance;

    constructor(string memory name, string memory symbol, address _fundsToken) ExtendedFDT(name, symbol) public {
        fundsToken = IERC20(_fundsToken);
    }

    /**
        @dev    Updates loss accounting for `msg.sender`, recognizing losses.
        @return losses The amount to be subtracted from a withdraw amount.
     */
    function _recognizeLosses() internal override returns (uint256 losses) {
        losses = _prepareLossesWithdraw();

        bptLosses = bptLosses.sub(losses);

        _updateLossesBalance();
    }

    /**
        @dev    Updates the current losses balance and returns the difference of the new and previous losses balance.
        @return The difference of the new and previous losses balance.
     */
    function _updateLossesBalance() internal override returns (int256) {
        uint256 _prevLossesTokenBalance = lossesBalance;

        lossesBalance = bptLosses;

        return int256(lossesBalance).sub(int256(_prevLossesTokenBalance));
    }

    /**
        @dev    Updates the current interest balance and returns the difference of the new and previous interest balance.
        @return The difference of the new and previous interest balance.
     */
    function _updateFundsTokenBalance() internal virtual override returns (int256) {
        uint256 _prevFundsTokenBalance = fundsTokenBalance;

        fundsTokenBalance = fundsToken.balanceOf(address(this));

        return int256(fundsTokenBalance).sub(int256(_prevFundsTokenBalance));
    }

}
