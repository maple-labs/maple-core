// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

import "./library/Util.sol";
import "./interfaces/IGlobals.sol";
import "./interfaces/IMapleToken.sol";
import "./interfaces/IERC20Details.sol";
import "./interfaces/IUniswapRouter.sol";

import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/SafeERC20.sol";

/// @title MapleTreasury earns revenue from Loans and distributes it to token holders and the Maple development team.
contract MapleTreasury {

    using SafeMath  for uint256;
    using SafeERC20 for IERC20;

    address public mpl;            // MapleToken contract
    address public fundsToken;     // fundsToken value in the MapleToken contract
    address public uniswapRouter;  // Official UniswapV2 router contract
    address public globals;        // MapleGlobals contract

    /**
        @dev Instantiates the MapleTreasury contract.
        @param  _mpl           MapleToken contract
        @param  _fundsToken    fundsToken of MapleToken contract
        @param  _uniswapRouter Official UniswapV2 router contract
        @param  _globals       MapleGlobals contract
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

    event ERC20Conversion(address asset, uint256 amountIn, uint256 amountOut);
    event PassThrough(uint256 amount);
    event FundsWithdrawn(uint256 amount);
    event FundsTokenModified(address by, address newFundsToken);

    modifier isGovernor() {
        require(msg.sender == IGlobals(globals).governor(), "MapleTreasury:MSG_SENDER_NOT_GOVERNOR");
        _;
    }

    /**
        @dev Update the MapleGlobals contract. Only Governor can set
        @param newGlobals Address of new MapleGlobals contract
    */
    function setGlobals(address newGlobals) external isGovernor {
        globals = newGlobals;
    }

    /**
        @dev Withdraws treasury funds to the MapleDAO address. Only Governor can call.
        @param asset  Address of the token that need to be reclaimed from the treasury contract
        @param amount Amount to withdraw
    */
    function withdrawFunds(address asset, uint256 amount) isGovernor public {
        IERC20(asset).safeTransfer(msg.sender, amount);
        emit FundsWithdrawn(amount);
    }

    /**
        @dev Passes through the current fundsToken balance of the treasury to MapleToken, where it can be claimed by MPL holders.
    */
    function distributeToHolders() isGovernor public {
        IERC20 _fundsToken = IERC20(fundsToken);
        uint256 passThroughAmount = _fundsToken.balanceOf(address(this));
        _fundsToken.safeTransfer(mpl, passThroughAmount);
        IMapleToken(mpl).updateFundsReceived();
        emit PassThrough(passThroughAmount);
    }

    /**
        @dev Convert an ERC-20 asset through Uniswap to fundsToken.
        @param asset The ERC-20 asset to convert to fundsToken
    */
    function convertERC20(address asset) isGovernor public {
        require(asset != fundsToken, "MapleTreasury:ASSET_EQUALS_FUNDS_TOKEN");
        
        IGlobals _globals = IGlobals(globals);

        uint256 assetBalance = IERC20(asset).balanceOf(address(this));
        uint256 minAmount    = Util.calcMinAmount(_globals, asset, fundsToken, assetBalance);

        IERC20(asset).safeIncreaseAllowance(uniswapRouter, assetBalance);

        address uniswapAssetForPath = _globals.defaultUniswapPath(asset, fundsToken);
        bool middleAsset = uniswapAssetForPath != fundsToken && uniswapAssetForPath != address(0);

        address[] memory path = new address[](middleAsset ? 3 : 2);

        path[0] = asset;
        path[1] = middleAsset ? uniswapAssetForPath : fundsToken;

        if(middleAsset) path[2] = fundsToken;

        uint256[] memory returnAmounts = IUniswapRouter(uniswapRouter).swapExactTokensForTokens(
            assetBalance,
            minAmount.sub(minAmount.mul(_globals.maxSwapSlippage()).div(10000)),
            path,
            address(this),
            block.timestamp
        );

        emit ERC20Conversion(asset, returnAmounts[0], returnAmounts[path.length - 1]);
    }
}
