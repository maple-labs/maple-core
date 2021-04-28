// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "../token/interfaces/IStakeLockerFDT.sol";

interface IStakeLocker is IStakeLockerFDT {
    function stakeDate(address) external returns (uint256);

    function stake(uint256) external;

    function unstake(uint256) external;

    function pull(address, uint256) external;

    function setAllowlist(address, bool) external;

    function openStakeLockerToPublic() external;

    function openToPublic() external view returns (bool);

    function allowed(address) external view returns (bool);

    function updateLosses(uint256) external;

    function intendToUnstake() external;

    function unstakeCooldown(address) external view returns (uint256);

    function lockupPeriod() external view returns (uint256);

    function stakeAsset() external view returns (address);

    function liquidityAsset() external view returns (address);

    function pool() external view returns (address);

    function setLockupPeriod(uint256) external;

    function cancelUnstake() external;

    function increaseCustodyAllowance(address, uint256) external;

    function transferByCustodian(address, address, uint256) external;

    function pause() external;

    function unpause() external;

    function isUnstakeAllowed(address) external view returns (bool);

    function isReceiveAllowed(uint256) external view returns (bool);
}
