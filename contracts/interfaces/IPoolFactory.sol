// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

interface IPoolFactory {
    function isPool(address _liquidityPool) external view returns (bool);
    function createPool(address, address, address, address,uint256, uint256, uint256) external returns (address);
    function pools(uint256) external view returns (address);
}
