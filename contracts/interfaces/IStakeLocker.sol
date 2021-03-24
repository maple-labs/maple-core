// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IStakeLocker is IERC20 {

    function stakeDate(address) external returns (uint256);

    function stake(uint256) external;

    function unstake(uint256) external;

    function withdrawUnstaked(uint256) external returns (uint256);

    function withdrawInterest() external returns (uint256);

    function updateFundsReceived() external;

    function withdrawableFundsOf(address) external view returns(uint256);

    function pull(address, uint256) external returns (bool);

    function setAllowlist(address, bool) external;

    function openStakeLockerToPublic(bool) external;

    function openToPublic() external view returns (bool);

    function allowed(address) external view returns (bool);

    function getUnstakeableBalance(address) external view returns (uint256);

    function updateLosses(uint256) external;

    function bptLosses() external view returns(uint256);

    function recognizableLossesOf(address) external view returns(uint256);

    function intendToUnstake() external;

    function stakeCooldown(address) external view returns(uint256);

}
