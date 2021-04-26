// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "./library/Util.sol";
import "./interfaces/IMapleGlobals.sol";
import "./interfaces/IMapleToken.sol";
import "./interfaces/IERC20Details.sol";
import "./interfaces/IUniswapRouter.sol";

import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/SafeERC20.sol";

/// @title MapleTreasury earns revenue from Loans and distributes it to token holders and the Maple development team.
contract MapleTreasury {

    using SafeMath  for uint256;
    using SafeERC20 for IERC20;

    address public immutable mpl;            // MapleToken contract
    address public immutable fundsToken;     // fundsToken value in the MapleToken contract
    address public immutable uniswapRouter;  // Official UniswapV2 router contract
    address public           globals;        // MapleGlobals contract

    /**
        @dev    Instantiates the MapleTreasury contract.
        @param  _mpl           MapleToken contract.
        @param  _fundsToken    fundsToken of MapleToken contract.
        @param  _uniswapRouter Official UniswapV2 router contract.
        @param  _globals       MapleGlobals contract.
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
        @dev Checks that msg.sender is the Governor.
    */
    modifier isGovernor() {
        require(msg.sender == IMapleGlobals(globals).governor(), "MT:NOT_GOV");
        _;
    }

    /**
        @dev   Update the MapleGlobals contract. Only the Governor can call this function.
        @dev   It emits a `GlobalsSet` event.
        @param newGlobals Address of new MapleGlobals contract.
    */
    function setGlobals(address newGlobals) isGovernor external {
        globals = newGlobals;
        emit GlobalsSet(newGlobals);
    }

    /**
        @dev   Reclaim treasury funds to the MapleDAO address. Only the Governor can call this function.
        @dev   It emits a `ERC20Reclaimed` event.
        @param asset  Address of the token that need to be reclaimed from the treasury contract,
        @param amount Amount to withdraw,
    */
    function reclaimERC20(address asset, uint256 amount) isGovernor external {
        IERC20(asset).safeTransfer(msg.sender, amount);
        emit ERC20Reclaimed(asset, amount);
    }

    /**
        @dev Passes through the current fundsToken balance of the treasury to MapleToken, where it can be claimed by MPL holders.
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
        @dev   Convert an ERC-20 asset through Uniswap to fundsToken. Only the Governor can call this function.
        @dev   It emits a `ERC20Conversion` event.
        @param asset The ERC-20 asset to convert to fundsToken.
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
