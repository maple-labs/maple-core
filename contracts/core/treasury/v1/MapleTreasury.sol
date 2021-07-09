// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { SafeMath } from "../../../../lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import { SafeERC20, IERC20 } from "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/SafeERC20.sol";

import { IMapleToken } from "../../../external-interfaces/IMapleToken.sol";
import { IUniswapRouter } from "../../../external-interfaces/IUniswapRouter.sol";

import { Util } from "../../../libraries/util/v1/Util.sol";

import { IMapleGlobals } from "../../globals/v1/interfaces/IMapleGlobals.sol";

import { IMapleTreasury } from "./interfaces/IMapleTreasury.sol";

/// @title MapleTreasury earns revenue from Loans and distributes it to token holders and the Maple development team.
contract MapleTreasury is IMapleTreasury {

    using SafeMath  for uint256;
    using SafeERC20 for IERC20;

    address public override immutable mpl;
    address public override immutable fundsToken;
    address public override immutable uniswapRouter;
    address public override           globals;

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

    /**
        @dev Checks that `msg.sender` is the Governor.
     */
    modifier isGovernor() {
        require(msg.sender == IMapleGlobals(globals).governor(), "MT:NOT_GOV");
        _;
    }

    function setGlobals(address newGlobals) isGovernor external override {
        globals = newGlobals;
        emit GlobalsSet(newGlobals);
    }

    function reclaimERC20(address asset, uint256 amount) isGovernor external override {
        IERC20(asset).safeTransfer(msg.sender, amount);
        emit ERC20Reclaimed(asset, amount);
    }

    function distributeToHolders() isGovernor external override {
        IERC20 _fundsToken = IERC20(fundsToken);
        uint256 distributeAmount = _fundsToken.balanceOf(address(this));
        _fundsToken.safeTransfer(mpl, distributeAmount);
        IMapleToken(mpl).updateFundsReceived();
        emit DistributedToHolders(distributeAmount);
    }

    function convertERC20(address asset) isGovernor external override {
        require(asset != fundsToken, "MT:ASSET_IS_FUNDS_TOKEN");

        IMapleGlobals _globals = IMapleGlobals(globals);

        uint256 assetBalance = IERC20(asset).balanceOf(address(this));
        uint256 minAmount    = Util.calcMinAmount(_globals, asset, fundsToken, assetBalance);

        IERC20(asset).safeApprove(uniswapRouter, uint256(0));
        IERC20(asset).safeApprove(uniswapRouter, assetBalance);

        address uniswapAssetForPath = _globals.defaultUniswapPath(asset, fundsToken);
        bool    middleAsset         = uniswapAssetForPath != fundsToken && uniswapAssetForPath != address(0);

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
