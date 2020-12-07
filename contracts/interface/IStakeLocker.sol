// SPDX-License-Identifier: MIT
pragma solidity 0.7.0;

interface IStakeLocker {
    function stake(uint256 _amountStakedAsset) external returns (uint256);

    function unstake(uint256 _amountStakedAsset) external returns (uint256);

    function withdrawUnstaked(uint256 _amountUnstaked) external returns (uint256);

    function withdrawInterest() external returns (uint256);

    function deleteLP() external;

    function finalizeLP() external;
}