// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "./IBaseFDT.sol";

/// @title BasicFDT implements the basic level FDT functionality for accounting for revenues.
interface IBasicFDT is IBaseFDT, IERC20 {

    /**
        @dev   This event emits when the internal `pointsPerShare` is updated.
        @param pointsPerShare The new value of the internal `pointsPerShare`.
     */
    event PointsPerShareUpdated(uint256 pointsPerShare);

    /**
        @dev   This event emits when an account's `pointsCorrection` is updated.
        @param account          The address of some account.
        @param pointsCorrection The new value of the account's `pointsCorrection`.
     */
    event PointsCorrectionUpdated(address indexed account, int256 pointsCorrection);

    /**
        @dev    Returns the amount of funds that an account has withdrawn.
        @param  account The address of a token holder.
        @return The amount of funds that `account` has withdrawn.
     */
    function withdrawnFundsOf(address account) external view returns (uint256);

    /**
        @dev    Returns the amount of funds that an account has earned in total. 
        @dev    accumulativeFundsOf(account) = withdrawableFundsOf(account) + withdrawnFundsOf(account) 
                = (pointsPerShare * balanceOf(account) + pointsCorrection[account]) / pointsMultiplier 
        @param  account The address of a token holder.
        @return The amount of funds that `account` has earned in total.
     */
    function accumulativeFundsOf(address account) external view returns (uint256);

    /**
        @dev Registers a payment of funds in tokens. 
        @dev May be called directly after a deposit is made. 
        @dev Calls _updateFundsTokenBalance(), whereby the contract computes the delta of the new and previous 
             `fundsToken` balance and increments the total received funds (cumulative), by delta, by calling _distributeFunds().
     */
    function updateFundsReceived() external;

}
