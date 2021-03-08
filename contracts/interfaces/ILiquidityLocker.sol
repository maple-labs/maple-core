// SPDX-License-Identifier: MIT
pragma solidity >=0.6.7;

interface ILiquidityLocker {
    function fundLoan(address, address, uint256) external;

    function transfer(address, uint256) external;
}
