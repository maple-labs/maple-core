// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IStakeLocker is IERC20 {
    function stakeDate(address) external returns (uint256);

    function stake(uint256) external;

    function unstake(uint256) external;

    function updateFundsReceived() external;

    function withdrawableFundsOf(address) external view returns(uint256);

    function pull(address, uint256) external;

    function setAllowlist(address, bool) external;

    function openStakeLockerToPublic() external;

    function openToPublic() external view returns (bool);

    function allowed(address) external view returns (bool);

    function updateLosses(uint256) external;

    function bptLosses() external view returns(uint256);

    function recognizableLossesOf(address) external view returns(uint256);

    function intendToUnstake() external;

    function unstakeCooldown(address) external view returns(uint256);

    function lockupPeriod() external view returns(uint256);

    function stakeAsset() external view returns (address);

    function liquidityAsset() external view returns (address);

    function pool() external view returns (address);

    function setLockupPeriod(uint256) external;
    
    function cancelUnstake() external;

    function withdrawFunds() external;

    function pause() external;

    function unpause() external;

    function isUnstakeAllowed(address) external view returns (bool);

    function isReceiveAllowed(uint256) external view returns (bool);
}
