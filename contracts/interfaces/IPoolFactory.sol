// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

interface IPoolFactory {
    function LL_FACTORY() external view returns (uint8);

    function SL_FACTORY() external view returns (uint8);

    function poolsCreated() external view returns (uint256);

    function globals() external view returns (address);

    function pools(uint256) external view returns (address);

    function isPool(address) external view returns (bool);

    function poolFactoryAdmins(address) external view returns (bool);

    function setGlobals(address) external;

    function createPool(address, address, address, address, uint256, uint256, uint256) external returns (address);

    function setPoolFactoryAdmin(address, bool) external;

    function pause() external;

    function unpause() external;
}
