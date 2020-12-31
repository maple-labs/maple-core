// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

interface ILiquidityPool {
    function poolDelegate() external view returns (address);

    function isDefunct() external view returns (bool);

    function isFinalized() external view returns (bool);
}