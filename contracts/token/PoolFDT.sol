// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

import "./ExtendedFDT.sol";

abstract contract PoolFDT is ExtendedFDT {
    using SafeMath       for uint256;
    using SafeMathUint   for uint256;
    using SignedSafeMath for  int256;
    using SafeMathInt    for  int256;

    uint256 public interestSum;   // Sum of all withdrawable interest 
    uint256 public bptShortfall;  // Sum of all unrecognized losses 

    uint256 public interestBalance;  // The amount of earned interest present and accounted for in this contract.
    uint256 public lossesBalance;    // The amount of losses present and accounted for in this contract.

    constructor(string memory name, string memory symbol) ExtendedFDT(name, symbol) public { }

    /**
        @dev Realizes losses incurred to LPs
    */
    function recognizeLosses() internal override returns (uint256 losses) {
        losses = _prepareLossesWithdraw();

        bptShortfall = bptShortfall.sub(losses);

        _updateLossesBalance();
    }

    /**
        @dev Updates the current funds token balance and returns the difference of new and previous funds token balances.
        @return A int256 representing the difference of the new and previous funds token balance.
    */
    function _updateLossesBalance() internal override returns (int256) {
        uint256 _prevLossesTokenBalance = lossesBalance;

        lossesBalance = bptShortfall;

        return int256(lossesBalance).sub(int256(_prevLossesTokenBalance));
    }

    /**
        @dev Updates the current funds token balance and returns the difference of new and previous funds token balances.
        @return A int256 representing the difference of the new and previous funds token balance.
    */
    function _updateFundsTokenBalance() internal override returns (int256) {
        uint256 _prevFundsTokenBalance = interestBalance;

        interestBalance = interestSum;

        return int256(interestBalance).sub(int256(_prevFundsTokenBalance));
    }

}
