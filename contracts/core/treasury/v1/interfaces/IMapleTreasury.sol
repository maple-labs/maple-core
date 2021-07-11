// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title MapleTreasury earns revenue from Loans and distributes it to token holders and the Maple development team.
interface IMapleTreasury {

    /**
        @dev   Emits an event indicating that an amount of some asset was converted to `fundsToken`.
        @param asset     The ERC-20 asset to convert to `fundsToken`.
        @param amountIn  The amount of the asset being converted to `fundsToken`.
        @param amountOut The amount of `fundsToken` received from the conversion.
     */
    event ERC20Conversion(address indexed asset, uint256 amountIn, uint256 amountOut);

    /**
        @dev   Emits an event indicating that a distribution was made to token holders.
        @param amount The amount distributed to token holders.
     */
    event DistributedToHolders(uint256 amount);
    
    /**
        @dev   Emits an event indicating the Governor reclaimed some token.
        @param asset  The address of the token to reclaimed.
        @param amount The amount reclaimed.
     */
    event ERC20Reclaimed(address indexed asset, uint256 amount);
    
    /**
        @dev   Emits an event indicating the MapleGlobals instance has changed.
        @param newGlobals The address of a new MapleGlobals.
     */
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
        @dev   Reclaims Treasury funds to the Governor. 
        @dev   Only the Governor can call this function. 
        @dev   It emits a `ERC20Reclaimed` event. 
        @param asset  The address of the token to be reclaimed.
        @param amount The amount reclaimed.
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
