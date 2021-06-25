// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title BasicFDT implements the basic level FDT functionality for accounting for revenues.
interface IBasicFDT is IERC20 {

    /**
        @dev   This event emits when new funds are distributed.
        @param by               The address of the sender that distributed funds.
        @param fundsDistributed The amount of funds received for distribution.
     */
    event FundsDistributed(address indexed by, uint256 fundsDistributed);

    /**
        @dev   This event emits when distributed funds are withdrawn by a token holder.
        @param by             The address of the receiver of funds.
        @param fundsWithdrawn The amount of funds that were withdrawn.
        @param totalWithdrawn The total amount of funds that were withdrawn.
     */
    event FundsWithdrawn(address indexed by, uint256 fundsWithdrawn, uint256 totalWithdrawn);

    /**
        @dev This event emits when the internal `pointsPerShare` is updated.
        @dev First, and only, parameter is the new value of the internal `pointsPerShare`.
     */
    event PointsPerShareUpdated(uint256);

    /**
        @dev This event emits when an account's `pointsCorrection` is updated.
        @dev First parameter is the address of some account.
        @dev Second parameter is the new value of the account's `pointsCorrection`.
     */
    event PointsCorrectionUpdated(address indexed, int256);

    /**
        @dev    Returns the amount of funds that an account can withdraw.
        @param  _owner The address of some FDT holder.
        @return The amount funds that `_owner` can withdraw.
     */
    function withdrawableFundsOf(address _owner) external view returns (uint256);

    /**
        @dev Withdraws all available funds for the calling FDT holder.
     */
    function withdrawFunds() external;

    /**
        @dev    Returns the amount of funds that an account has withdrawn.
        @param  _owner The address of a token holder.
        @return The amount of funds that `_owner` has withdrawn.
     */
    function withdrawnFundsOf(address _owner) external view returns (uint256);

    /**
        @dev    Returns the amount of funds that an account has earned in total. 
        @dev    accumulativeFundsOf(_owner) = withdrawableFundsOf(_owner) + withdrawnFundsOf(_owner) 
                = (pointsPerShare * balanceOf(_owner) + pointsCorrection[_owner]) / pointsMultiplier 
        @param  _owner The address of a token holder.
        @return The amount of funds that `_owner` has earned in total.
     */
    function accumulativeFundsOf(address _owner) external view returns (uint256);

    /**
        @dev Registers a payment of funds in tokens. 
        @dev May be called directly after a deposit is made. 
        @dev Calls _updateFundsTokenBalance(), whereby the contract computes the delta of the new and previous 
             `fundsToken` balance and increments the total received funds (cumulative), by delta, by calling _distributeFunds().
     */
    function updateFundsReceived() external;

}
