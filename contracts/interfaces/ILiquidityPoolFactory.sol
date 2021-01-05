// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

interface ILiquidityPoolFactory {
    function isLiquidityPool(address _liquidityPool) external view returns (bool);
    function createLiquidityPool(address, address, uint256, uint256) external returns (address);
}
