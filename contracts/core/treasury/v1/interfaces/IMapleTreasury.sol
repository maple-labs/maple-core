// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title MapleTreasury earns revenue from Loans and distributes it to token holders and the Maple development team.
interface IMapleTreasury {

    event ERC20Conversion(address indexed asset, uint256 amountIn, uint256 amountOut);

    event DistributedToHolders(uint256 amount);
    
    event ERC20Reclaimed(address indexed asset, uint256 amount);
    
    event GlobalsSet(address newGlobals);

    /**
        @dev The address of ERC-2222 Maple Token for the Maple protocol.
     */
    function mpl() external view returns (address);

    /**
        @dev The address of the `fundsToken` of the ERC-2222 Maple Token.
     */
    function fundsToken() external view returns (address);

    /**
        @dev The address of the official UniswapV2 router.
     */
    function uniswapRouter() external view returns (address);

    /**
        @dev The address of an instance of MapleGlobals.
     */
    function globals() external view returns (address);

    /**
        @dev   Updates the MapleGlobals instance. 
        @dev   Only the Governor can call this function. 
        @dev   It emits a `GlobalsSet` event. 
        @param newGlobals The address of a new MapleGlobals instance.
     */
    function setGlobals(address newGlobals) external;

    /**
        @dev   Reclaims Treasury funds to the MapleDAO address. 
        @dev   Only the Governor can call this function. 
        @dev   It emits a `ERC20Reclaimed` event. 
        @param asset  The address of the token to be reclaimed.
        @param amount The amount to withdraw.
     */
    function reclaimERC20(address asset, uint256 amount) external;

    /**
        @dev Passes through the current `fundsToken` balance of the Treasury to Maple Token, where it can be claimed by MPL holders. 
        @dev Only the Governor can call this function. 
        @dev It emits a `DistributedToHolders` event. 
     */
    function distributeToHolders() external;

    /**
        @dev   Converts an ERC-20 asset, via Uniswap, to `fundsToken`. 
        @dev   Only the Governor can call this function. 
        @dev   It emits a `ERC20Conversion` event. 
        @param asset The ERC-20 asset to convert to `fundsToken`.
     */
    function convertERC20(address asset) external;

}
