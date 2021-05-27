// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

interface IMplRewardsFactory {

    function globals() external view returns (address);

    function isMplRewards(address) external view returns (bool);

    function setGlobals(address _globals) external;

    function createMplRewards(address rewardsToken, address stakingToken) external returns (address mplRewards);

}
