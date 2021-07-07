// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.6.11;

import "../../MplRewards.sol";

contract MplRewardsOwner {
    function mplRewards_transferOwnership(MplRewards mplRewards, address newOwner) external {
        mplRewards.transferOwnership(newOwner);
    }

    function try_mplRewards_transferOwnership(address mplRewards, address newOwner) external returns (bool ok) {
        (ok,) = mplRewards.call(abi.encodeWithSignature("transferOwnership(address)", newOwner));
    }

    function mplRewards_notifyRewardAmount(MplRewards mplRewards, uint256 amount) external {
        mplRewards.notifyRewardAmount(amount);
    }

    function try_mplRewards_notifyRewardAmount(address mplRewards, uint256 amount) external returns (bool ok) {
        (ok,) = mplRewards.call(abi.encodeWithSignature("notifyRewardAmount(uint256)", amount));
    }

    function mplRewards_updatePeriodFinish(MplRewards mplRewards, uint256 periodFinish) external {
        mplRewards.updatePeriodFinish(periodFinish);
    }

    function try_mplRewards_updatePeriodFinish(address mplRewards, uint256 periodFinish) external returns (bool ok) {
        (ok,) = mplRewards.call(abi.encodeWithSignature("updatePeriodFinish(uint256)", periodFinish));
    }

    function mplRewards_recoverERC20(MplRewards mplRewards, address tokenAddress, uint256 amount) external {
        mplRewards.recoverERC20(tokenAddress, amount);
    }

    function try_mplRewards_recoverERC20(address mplRewards, address tokenAddress, uint256 amount) external returns (bool ok) {
        (ok,) = mplRewards.call(abi.encodeWithSignature("recoverERC20(address,uint256)", tokenAddress, amount));
    }

    function mplRewards_setRewardsDuration(MplRewards mplRewards, uint256 duration) external {
        mplRewards.setRewardsDuration(duration);
    }

    function try_mplRewards_setRewardsDuration(address mplRewards, uint256 duration) external returns (bool ok) {
        (ok,) = mplRewards.call(abi.encodeWithSignature("setRewardsDuration(uint256)", duration));
    }

    function mplRewards_setPaused(MplRewards mplRewards, bool paused) external {
        mplRewards.setPaused(paused);
    }

    function try_mplRewards_setPaused(address mplRewards, bool paused) external returns (bool ok) {
        (ok,) = mplRewards.call(abi.encodeWithSignature("setPaused(bool)", paused));
    }
}
