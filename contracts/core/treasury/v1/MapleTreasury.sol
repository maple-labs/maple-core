// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/SafeERC20.sol";

import "core/globals/v1/interfaces/IMapleGlobals.sol";
import "./interfaces/IMapleToken.sol";
import "external-interfaces/IUniswapRouter.sol";

import "libraries/util/v1/Util.sol";

/// @title MapleTreasury earns revenue from Loans and distributes it to token holders and the Maple development team.
contract MapleTreasury {

    using SafeMath  for uint256;
    using SafeERC20 for IERC20;

    address public immutable mpl;            // The address of ERC-2222 Maple Token for the Maple protocol.
    address public immutable fundsToken;     // The address of the `fundsToken` of the ERC-2222 Maple Token.
    address public immutable uniswapRouter;  // The address of the official UniswapV2 router.
    address public           globals;        // The address of an instance of MapleGlobals.

    /**
        @dev   Instantiates the MapleTreasury contract.
        @param _mpl           The address of ERC-2222 Maple Token for the Maple protocol.
        @param _fundsToken    The address of the `fundsToken` of the ERC-2222 Maple Token.
        @param _uniswapRouter The address of the official UniswapV2 router.
        @param _globals       The address of an instance of MapleGlobals.
    */
    constructor(
        address _mpl,
        address _fundsToken,
        address _uniswapRouter,
        address _globals
    ) public {
        mpl           = _mpl;
        fundsToken    = _fundsToken;
        uniswapRouter = _uniswapRouter;
        globals       = _globals;
    }

    event      ERC20Conversion(address indexed asset, uint256 amountIn, uint256 amountOut);
    event DistributedToHolders(uint256 amount);
    event       ERC20Reclaimed(address indexed asset, uint256 amount);
    event           GlobalsSet(address newGlobals);

    /**
        @dev Checks that `msg.sender` is the Governor.
    */
    modifier isGovernor() {
        require(msg.sender == IMapleGlobals(globals).governor(), "MT:NOT_GOV");
        _;
    }

    /**
        @dev   Updates the MapleGlobals instance. Only the Governor can call this function.
        @dev   It emits a `GlobalsSet` event.
        @param newGlobals Address of a new MapleGlobals instance.
    */
    function setGlobals(address newGlobals) isGovernor external {
        globals = newGlobals;
        emit GlobalsSet(newGlobals);
    }

    /**
        @dev   Reclaims Treasury funds to the MapleDAO address. Only the Governor can call this function.
        @dev   It emits a `ERC20Reclaimed` event.
        @param asset  Address of the token to be reclaimed.
        @param amount Amount to withdraw.
    */
    function reclaimERC20(address asset, uint256 amount) isGovernor external {
        IERC20(asset).safeTransfer(msg.sender, amount);
        emit ERC20Reclaimed(asset, amount);
    }

    /**
        @dev Passes through the current `fundsToken` balance of the Treasury to Maple Token, where it can be claimed by MPL holders.
             Only the Governor can call this function.
        @dev It emits a `DistributedToHolders` event.
    */
    function distributeToHolders() isGovernor external {
        IERC20 _fundsToken = IERC20(fundsToken);
        uint256 distributeAmount = _fundsToken.balanceOf(address(this));
        _fundsToken.safeTransfer(mpl, distributeAmount);
        IMapleToken(mpl).updateFundsReceived();
        emit DistributedToHolders(distributeAmount);
    }

    /**
        @dev   Converts an ERC-20 asset, via Uniswap, to `fundsToken`. Only the Governor can call this function.
        @dev   It emits a `ERC20Conversion` event.
        @param asset The ERC-20 asset to convert to `fundsToken`.
    */
    function convertERC20(address asset) isGovernor external {
        require(asset != fundsToken, "MT:ASSET_IS_FUNDS_TOKEN");

        IMapleGlobals _globals = IMapleGlobals(globals);

        uint256 assetBalance = IERC20(asset).balanceOf(address(this));
        uint256 minAmount    = Util.calcMinAmount(_globals, asset, fundsToken, assetBalance);

        IERC20(asset).safeApprove(uniswapRouter, uint256(0));
        IERC20(asset).safeApprove(uniswapRouter, assetBalance);

        address uniswapAssetForPath = _globals.defaultUniswapPath(asset, fundsToken);
        bool middleAsset            = uniswapAssetForPath != fundsToken && uniswapAssetForPath != address(0);

        address[] memory path = new address[](middleAsset ? 3 : 2);

        path[0] = asset;
        path[1] = middleAsset ? uniswapAssetForPath : fundsToken;

        if (middleAsset) path[2] = fundsToken;

        uint256[] memory returnAmounts = IUniswapRouter(uniswapRouter).swapExactTokensForTokens(
            assetBalance,
            minAmount.sub(minAmount.mul(_globals.maxSwapSlippage()).div(10_000)),
            path,
            address(this),
            block.timestamp
        );

        emit ERC20Conversion(asset, returnAmounts[0], returnAmounts[path.length - 1]);
    }

}
