// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;


interface IStakingRewards {
    // Views
    function lastTimeRewardApplicable() external view returns (uint256);

    function rewardPerToken() external view returns (uint256);

    function earned(address) external view returns (uint256);

    function getRewardForDuration() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function balanceOf(address) external view returns (uint256);

    // Mutative
    function stake(uint256) external;

    function withdraw(uint256) external;

    function getReward() external;

    function exit() external;
}
