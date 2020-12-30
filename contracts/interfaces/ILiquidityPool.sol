// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

interface ILiquidityPool {
    function poolDelegate() external view returns (address);

    function isDefunct() external view returns (bool);

    function isFinalized() external view returns (bool);

    function deposit(uint256) external;

    function claim(address, address) external returns(uint, uint, uint, uint, uint);
}
