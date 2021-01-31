// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IStakeLocker is IERC20 {
    function stakeDate(address) external returns (uint256);
    function stake(uint256) external;
    function unstake(uint256 _amountStakedAsset) external;
    function withdrawUnstaked(uint256 _amountUnstaked) external returns (uint256);
    function withdrawInterest() external returns (uint256);
    function updateFundsReceived() external;
    function withdrawableFundsOf(address) external view returns(uint256);
    function pull(address, uint256) external returns (bool);
}
