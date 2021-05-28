// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

interface ILiquidityLocker {

    function pool() external view returns (address);

    function liquidityAsset() external view returns (address);

    function transfer(address, uint256) external;

    function fundLoan(address, address, uint256) external;

}
