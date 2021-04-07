// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

interface IPoolFactory {
    function isPool(address) external view returns (bool);

    function createPool(address, address, address, address,uint256, uint256, uint256) external returns (address);

    function pools(uint256) external view returns (address);

    function globals() external view returns (address);
}
