// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

interface IMplRewards {

    // Views
    function rewardsToken() external view returns (address);

    function stakingToken() external view returns (address);

    function periodFinish() external view returns (uint256);

    function rewardRate() external view returns (uint256);

    function rewardsDuration() external view returns (uint256);

    function lastUpdateTime() external view returns (uint256);

    function rewardPerTokenStored() external view returns (uint256);

    function lastPauseTime() external view returns (uint256);

    function paused() external view returns (bool);

    function userRewardPerTokenPaid(address) external view returns (uint256);

    function rewards(address) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function balanceOf(address) external view returns (uint256);

    function lastTimeRewardApplicable() external view returns (uint256);

    function rewardPerToken() external view returns (uint256);

    function earned(address) external view returns (uint256);

    function getRewardForDuration() external view returns (uint256);


    // Mutative
    function stake(uint256) external;

    function withdraw(uint256) external;

    function getReward() external;

    function exit() external;

    function notifyRewardAmount(uint256) external;

    function updatePeriodFinish(uint256) external;

    function recoverERC20(address, uint256) external;

    function setRewardsDuration(uint256) external;

    function setPaused(bool) external;

}
