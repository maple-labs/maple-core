// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

/// @title BaseFDT implements the common level FDT functionality for accounting for revenues.
interface IBaseFDT {

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
        @dev    Returns the amount of funds that an account can withdraw.
        @param  account The address of some FDT holder.
        @return The amount funds that `account` can withdraw.
     */
    function withdrawableFundsOf(address account) external view returns (uint256);

    /**
        @dev Withdraws all available funds for the calling FDT holder.
     */
    function withdrawFunds() external;

}
