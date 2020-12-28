// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

interface IStakeLocker {

    function stakeDate(address) external returns (uint256);

    function stake(uint256) external;

    function unstake(uint256 _amountStakedAsset) external returns (uint256);

    function withdrawUnstaked(uint256 _amountUnstaked) external returns (uint256);

    function withdrawInterest() external returns (uint256);

    function deleteLP() external;

    function finalizeLP() external;
}
