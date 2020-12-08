// SPDX-License-Identifier: MIT
pragma solidity 0.7.0;

interface ILiquidityPoolFactory {
    function isLiquidityPool(address _liquidityPool) external view returns (bool);
}
