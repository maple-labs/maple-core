// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { IERC20 } from "../../../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { IStakeLockerFDT } from "./IStakeLockerFDT.sol";

/// @title StakeLocker holds custody of stakeAsset tokens for a given Pool and earns revenue from interest.
interface IStakeLocker is IStakeLockerFDT {

    /**
        @dev   Emits an event indicating that the Stake Locker is now open to the public.
     */
    event StakeLockerOpened();

    /**
        @dev   Emits an event indicating some Balance was updated.
        @param staker  The address of a Staker.
        @param token   The address of the token for which the balance of `staker` changed.
        @param balance The new balance for `staker`.
     */
    event BalanceUpdated(address indexed staker, address indexed token, uint256 balance);

    /**
        @dev   Emits an event indicating that the ability of `staker` to stake before the locker is open to the public, has changed.
        @param staker The address of some account.
        @param status Whether `staker` can stake before the locker is open to the public.
     */
    event AllowListUpdated(address indexed staker, bool status);

    /**
        @dev   Emits an event indicating a that a Staker's effective stake date has changed.
        @param staker    The address of a Staker.
        @param stakeDate The new effective stake date.
     */
    event StakeDateUpdated(address indexed staker, uint256 stakeDate);

    /**
        @dev   Emits an event indicating that the stake lockup period has changed.
        @param lockupPeriod The new stake lockup period.
     */
    event LockupPeriodUpdated(uint256 lockupPeriod);

    /**
        @dev   Emits an event indicating that the cooldown timestamp for a staker has changed.
        @param staker   The address of a Staker.
        @param cooldown The new cooldown timestamp for `staker`.
     */
    event Cooldown(address indexed staker, uint256 cooldown);

    /**
        @dev   Emits an event indicating `staker` has added `amount` to the total they have staked.
        @param staker The address of a Staker.
        @param amount The additional amount staked.
     */
    event Stake(address indexed staker, uint256 amount);

    /**
        @dev   Emits an event indicating `staker` has removed `amount` from the total they have staked.
        @param staker The address of a Staker.
        @param amount The amount unstaked.
     */
    event Unstake(address indexed staker, uint256 amount);

    /**
        @dev   Emits an event indicating that a Custodian transferred some StakeLockerFDTs for purposes of custody.
        @param custodian The address of the Custodian initiating the transfer.
        @param from      The account that owns the StakeLockerFDTs.
        @param to        The address of a Custodian taking custody of the amount.
        @param amount    The amount of StakeLockerFDTs being re-custodied.
     */
    event CustodyTransfer(address indexed custodian, address indexed from, address indexed to, uint256 amount);

    /**
        @dev   Emits an event indicating that the amount being custodied by a Custodian, on behalf of a Staker, has changed.
        @param staker       The address of a Staker.
        @param custodian    The address of a Custodian.
        @param oldAllowance The old amount of StakeLockerFDTs `custodian` had custodied on behalf of `staker`.
        @param newAllowance The new amount of StakeLockerFDTs `custodian` has custodied on behalf of `staker`.
     */
    event CustodyAllowanceChanged(address indexed staker, address indexed custodian, uint256 oldAllowance, uint256 newAllowance);

    /**
        @dev   Emits an event indicating that the total amount of StakeLockerFDTs custodied, on behalf of a Staker, by all custodians, has changed.
        @param staker            The address of a Staker.
        @param newTotalAllowance The total amount of StakeLockerFDTs custodied, on behalf of `staker`, by all custodians.
     */
    event TotalCustodyAllowanceUpdated(address indexed staker, uint256 newTotalAllowance);

    /**
        @dev The asset deposited by Stakers into this contract, for liquidation during defaults.
     */
    function stakeAsset() external view returns (IERC20);

    /**
        @dev The Liquidity Asset for the Pool as well as the dividend token for StakeLockerFDT interest.
     */
    function liquidityAsset() external view returns (address);

    /**
        @dev The parent Pool.
     */
    function pool() external view returns (address);

    /**
        @dev The number of seconds for which unstaking is not allowed.
     */
    function lockupPeriod() external view returns (uint256);

    /**
        @param  account The address of a Staker.
        @return The effective stake date of `account`.
     */
    function stakeDate(address account) external returns (uint256);

    /**
        @param  account The address of a Staker.
        @return The timestamp of when `account` called `cooldown()`.
     */
    function unstakeCooldown(address account) external view returns (uint256);

    /**
        @param  account The address of a Staker.
        @return Whether `account` is allowed.
     */
    function allowed(address account) external view returns (bool);

    /**
        @param  account   The address of an account.
        @param  custodian The address of a custodian.
        @return The amount of StakeLockerFDTs of `account` that are "locked" at `custodian`.
     */
    function custodyAllowance(address account, address custodian) external view returns (uint256);

    /**
        @param  account   The address of an account.
        @return The total amount of StakeLockerFDTs that are "locked" for a given account, cannot be greater than balance.
     */
    function totalCustodyAllowance(address account) external view returns (uint256);

    function openToPublic() external view returns (bool);

    /**
        @dev   Updates Staker status on the allowlist. 
        @dev   Only the Pool Delegate can call this function. 
        @dev   It emits an `AllowListUpdated` event. 
        @param staker The address of the Staker to set status for.
        @param status The status of the Staker on allowlist.
     */
    function setAllowlist(address staker, bool status) external;

    /**
        @dev Sets the StakeLocker as open to the public. 
        @dev Only the Pool Delegate can call this function. 
        @dev It emits a `StakeLockerOpened` event. 
     */
    function openStakeLockerToPublic() external;

    /**
        @dev   Sets the lockup period. 
        @dev   Only the Pool Delegate can call this function. 
        @dev   It emits a `LockupPeriodUpdated` event. 
        @param newLockupPeriod New lockup period used to restrict unstaking.
     */
    function setLockupPeriod(uint256 newLockupPeriod) external;

    /**
        @dev   Transfers an amount of Stake Asset to a destination account. 
        @dev   Only the Pool can call this function. 
        @param dst The destination to transfer Stake Asset to.
        @param amt The amount of Stake Asset to transfer.
     */
    function pull(address dst, uint256 amt) external;

    /**
        @dev   Updates loss accounting for StakeLockerFDTs after BPTs have been burned. 
        @dev   Only the Pool can call this function. 
        @param bptsBurned The amount of BPTs that have been burned.
     */
    function updateLosses(uint256 bptsBurned) external;

    /**
        @dev   Handles a Staker's depositing of an amount of Stake Asset, minting them StakeLockerFDTs. 
        @dev   It emits a `StakeDateUpdated` event. 
        @dev   It emits a `Stake` event. 
        @dev   It emits a `Cooldown` event. 
        @dev   It emits a `BalanceUpdated` event. 
        @param amt The amount of Stake Asset (BPTs) to deposit.
     */
    function stake(uint256 amt) external;

    /**
        @dev Activates the cooldown period to unstake. 
        @dev It can't be called if the account is not staking. 
        @dev It emits a `Cooldown` event. 
     */
    function intendToUnstake() external;

    /**
        @dev Cancels an initiated unstake by resetting the calling account's unstake cooldown. 
        @dev It emits a `Cooldown` event. 
     */
    function cancelUnstake() external;

    /**
        @dev   Handles a Staker's withdrawing of an amount of Stake Asset, minus any losses. 
        @dev   It also claims interest and burns StakeLockerFDTs for the calling account. 
        @dev   It emits an `Unstake` event. 
        @dev   It emits a `BalanceUpdated` event. 
        @param amt The amount of Stake Asset (BPTs) to withdraw.
     */
    function unstake(uint256 amt) external;

    /**
        @dev Withdraws all claimable interest earned from the StakeLocker for an account. 
        @dev It emits a `BalanceUpdated` event if there are withdrawable funds. 
     */
    function withdrawFunds() external override;    

    /**
        @dev   Increases the custody allowance for a given Custodian corresponding to the account (`msg.sender`).
        @dev   It emits a `CustodyAllowanceChanged` event.
        @dev   It emits a `TotalCustodyAllowanceUpdated` event.
        @param custodian The address which will act as Custodian of a given amount for an account.
        @param amount    The number of additional FDTs to be custodied by the Custodian.
     */
    function increaseCustodyAllowance(address custodian, uint256 amount) external;

    /**
        @dev   Transfers custodied StakeLockerFDTs back to the account. 
        @dev   `from` and `to` should always be equal in this implementation. 
        @dev   This means that the Custodian can only decrease their own allowance and unlock funds for the original owner. 
        @dev   It emits a `CustodyTransfer` event. 
        @dev   It emits a `CustodyAllowanceChanged` event. 
        @dev   It emits a `TotalCustodyAllowanceUpdated` event. 
        @param from   The address which holds the StakeLockerFDTs.
        @param to     The address which will be the new owner of the amount of StakeLockerFDTs.
        @param amount The mount of StakeLockerFDTs transferred.
     */
    function transferByCustodian(address from, address to, uint256 amount) external;

    /**
        @dev Triggers paused state. 
        @dev Halts functionality for certain functions. 
        @dev Only the Pool Delegate or a Pool Admin can call this function. 
     */
    function pause() external;

    /**
        @dev Triggers unpaused state. 
        @dev Restores functionality for certain functions. 
        @dev Only the Pool Delegate or a Pool Admin can call this function.
     */
    function unpause() external;

    /**
        @dev Returns if the unstake cooldown period has passed for `msg.sender` and if they are in the unstake window.
     */
    function isUnstakeAllowed(address from) external view returns (bool);

    /**
        @dev Returns if an account is allowed to receive a transfer. 
        @dev This is only possible if they have zero cooldown or they are past their unstake window. 
     */
    function isReceiveAllowed(uint256 _unstakeCooldown) external view returns (bool);

}
