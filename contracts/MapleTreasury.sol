// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "./library/Util.sol";
import "./interfaces/IGlobals.sol";
import "./interfaces/IMapleToken.sol";
import "./interfaces/IERC20Details.sol";
import "./interfaces/IUniswapRouter.sol";

import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract MapleTreasury {

	using SafeMath for uint256;

    address public mpl;            // MapleToken.sol contract.
    address public fundsToken;     // fundsToken value in the MapleToken.sol contract.
    address public uniswapRouter;  // Official UniswapV2 router contract.
    address public globals;        // MapleGlobals.sol contract.

    /**
        @dev Instantiates the MapleTreasury contract.
        @param  _mpl is the MapleToken contract.
        @param  _fundsToken is the fundsToken of MapleToken contract.
        @param  _uniswapRouter is the official UniswapV2 router contract.
        @param  _globals is the MapleGlobals.sol contract.
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
        @dev Update the maple globals contract
        @param newGlobals Address of new maple globals contract
    */
    function setGlobals(address newGlobals) external isGovernor {
        globals = newGlobals;
    }

    /**
        @dev Withdraws treasury funds to the MapleDAO address
        @param asset  Address of the token that need to be reclaimed from the treasury contract.
        @param amount The new FundsToken with respect to MapleToken ERC-2222.
    */
    function withdrawFunds(address asset, uint256 amount) isGovernor public {
        require(IERC20(asset).transfer(msg.sender, amount), "MapleTreasury:FUNDS_RECEIVE_TRANSFER");
        emit FundsWithdrawn(amount);
    }

    /**
        @dev Passes through the current fundsToken to MapleToken, where they can be claimed by MPL holders.
    */
    function distributeToHolders() isGovernor public {
        IERC20 _fundsToken = IERC20(fundsToken);
        uint256 passThroughAmount = _fundsToken.balanceOf(address(this));
        require(_fundsToken.transfer(mpl, passThroughAmount), "MapleTreasury:FUNDS_RECEIVE_TRANSFER");
        IMapleToken(mpl).updateFundsReceived();
        emit PassThrough(passThroughAmount);
    }

    /**
        @dev Convert an ERC-20 asset through Uniswap to fundsToken
        @param asset The ERC-20 asset to convert.
    */
    function convertERC20(address asset) isGovernor public {
        require(asset != fundsToken, "MapleTreasury:ASSET_EQUALS_FUNDS_TOKEN");
        
        IGlobals _globals = IGlobals(globals);

        uint256 assetBalance = IERC20(asset).balanceOf(address(this));
        uint256 minAmount    = Util.calcMinAmount(_globals, asset, fundsToken, assetBalance);

        IERC20(asset).approve(uniswapRouter, assetBalance);

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
