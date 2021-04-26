// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

interface IMapleTreasury {
    function mpl() external view returns (address);

    function fundsToken() external view returns (address);

    function uniswapRouter() external view returns (address);

    function globals() external view returns (address);

    function setGlobals(address) external;

    function reclaimERC20(address, uint256) external;

    function distributeToHolders() external;

    function convertERC20(address) external;
}
