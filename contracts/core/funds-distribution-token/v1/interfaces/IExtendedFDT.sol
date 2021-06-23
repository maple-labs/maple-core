// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "./IBasicFDT.sol";

/// @title ExtendedFDT implements the FDT functionality for accounting for losses.
interface IExtendedFDT is IBasicFDT {

    /**
        @dev   This event emits when the internal `lossesPerShare` is updated.
        @param lossesPerShare The new value of the internal `lossesPerShare`.
     */
    event LossesPerShareUpdated(uint256 lossesPerShare);

    /**
        @dev   This event emits when an account's `lossesCorrection` is updated.
        @param account          The address of some account.
        @param lossesCorrection The new value of the account's `lossesCorrection`.
     */
    event LossesCorrectionUpdated(address indexed account, int256 lossesCorrection);

    /**
        @dev   This event emits when new losses are distributed.
        @param by                The address of the account that has distributed losses.
        @param lossesDistributed The amount of losses received for distribution.
     */
    event LossesDistributed(address indexed by, uint256 lossesDistributed);

    /**
        @dev   This event emits when distributed losses are recognized by a token holder.
        @param by                    The address of the receiver of losses.
        @param lossesRecognized      The amount of losses that were recognized.
        @param totalLossesRecognized The total amount of losses that are recognized.
     */
    event LossesRecognized(address indexed by, uint256 lossesRecognized, uint256 totalLossesRecognized);

    /**
        @dev    Returns the amount of losses that an account can withdraw.
        @param  _owner The address of a token holder.
        @return The amount of losses that `_owner` can withdraw.
     */
    function recognizableLossesOf(address _owner) external view returns (uint256);

    /**
        @dev    Returns the amount of losses that an account has recognized.
        @param  _owner The address of a token holder.
        @return The amount of losses that `_owner` has recognized.
     */
    function recognizedLossesOf(address _owner) external view returns (uint256);

    /**
        @dev    Returns the amount of losses that an account has earned in total. 
        @dev    accumulativeLossesOf(_owner) = recognizableLossesOf(_owner) + recognizedLossesOf(_owner) 
                = (lossesPerShare * balanceOf(_owner) + lossesCorrection[_owner]) / pointsMultiplier 
        @param  _owner The address of a token holder.
        @return The amount of losses that `_owner` has earned in total.
     */
    function accumulativeLossesOf(address _owner) external view returns (uint256);

    /**
        @dev Registers a loss. 
        @dev May be called directly after a shortfall after BPT burning occurs. 
        @dev Calls _updateLossesTokenBalance(), whereby the contract computes the delta of the new and previous 
             losses balance and increments the total losses (cumulative), by delta, by calling _distributeLosses(). 
     */
    function updateLossesReceived() external;

}
