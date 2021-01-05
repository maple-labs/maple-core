// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IGlobals.sol";
import "./interfaces/IUniswapRouter.sol";
import "./interfaces/IMapleToken.sol";

contract MapleTreasury {

	using SafeMath for uint256;

  /// @notice mapletoken is the MapleToken.sol contract.
  address public mapleToken;

  /// @notice fundsToken is the _fundsToken value in the MapleToken.sol contract.
  address public fundsToken;

  /// @notice uniswapRouter is the official UniswapV2 router contract.
  address public uniswapRouter;

  /// @notice mapleGlobals is the MapleGlobals.sol contract.
  address public mapleGlobals;

  /// @notice Instantiates the MapleTreasury contract.
  /// @param _mapleToken is the MapleToken.sol contract.
  /// @param _fundsToken is the _fundsToken value in the MapleToken.sol contract.
  /// @param _uniswapRouter is the official UniswapV2 router contract.
  /// @param _mapleGlobals is the MapleGlobals.sol contract.
  constructor(
    address _mapleToken, 
    address _fundsToken, 
    address _uniswapRouter,
    address _mapleGlobals
  ) public {
    mapleToken = _mapleToken;
    fundsToken = _fundsToken;
    uniswapRouter = _uniswapRouter;
    mapleGlobals = _mapleGlobals;
  }

  /// @notice Fired when an ERC-20 asset is converted to fundsToken and transferred to mapleToken.
  /// @param _asset The asset that is converted.
  /// @param _by The msg.sender calling the conversion function.
  /// @param _amountIn The amount of _asset converted to fundsToken.
  /// @param _amountOut The amount of fundsToken received for _asset conversion.
  event ERC20Conversion(
    address _asset,
    address _by,
    uint256 _amountIn,
    uint256 _amountOut
  );

  /// @notice Fired when ETH is converted to fundsToken and transferred to mapleToken.
  /// @param _by The msg.sender calling the conversion function.
  /// @param _amountIn The amount of ETH converted to fundsToken.
  /// @param _amountOut The amount of fundsToken received for ETH conversion.
  event ETHConversion(
    address _by,
    uint256 _amountIn,
    uint256 _amountOut
  );

  /// @notice Fired when fundsToken is passed through to mapleToken.
  event PassThrough(
    address _by,
    uint256 _amount
  );

  /// @notice Fired when fundsToken is passed through to mapleToken.
  event FundsTokenModified(
    address _by,
    address _newFundsToken
  );

  // Authorization to call Treasury functions.
  modifier isGovernor() {
      require(msg.sender == IGlobals(mapleGlobals).governor(), "msg.sender is not Governor");
      _;
  }
  
  // Fallback and receive functions for native ETH.
  fallback () external payable { }
  receive () external payable { }

  /// @notice Adjust the token to convert assets to (and then send to MapleToken).
  /// @param _newFundsToken The new FundsToken with respect to MapleToken ERC-2222.
  function setFundsToken(address _newFundsToken) isGovernor public {
    fundsToken = _newFundsToken;
  }

  /// @notice Passes through the current fundsToken to MapleToken.
  function passThroughFundsToken() isGovernor public {
    emit PassThrough(
      msg.sender,
      IERC20(fundsToken).balanceOf(address(this))
    );
    require(
      IERC20(fundsToken).transfer(mapleToken, IERC20(fundsToken).balanceOf(address(this))), 
      "MapleTreasury::passThroughFundsToken:FUNDS_RECEIVE_TRANSFER_ERROR"
    );
  }

  /**
   TODO:  Implement price oracle to ensure best quality execution (1% slippage) ...
          and also to prevent front-running of transactions.
          The price feed should be used for USDC conversion, supplied in the ...
          2nd parameter of the swapExactTokensForTokens() function.
  */

  /// @notice Convert an ERC-20 asset through Uniswap via bilateral transaction (two asset path).
  /// @param _asset The ERC-20 asset to convert.
  function convertERC20(address _asset) isGovernor public {
    require(_asset != fundsToken, "MapleTreasury::convertERC20:ERR_ASSET");
    require(
      IERC20(_asset).approve(uniswapRouter, IERC20(_asset).balanceOf(address(this))), 
      "MapleTreasury::convertERC20:ROUTER_APPROVE_FAIL"
    );
    address[] memory path = new address[](2);
    path[0] = _asset;
    path[1] = fundsToken;
    uint[] memory returnAmounts = IUniswapRouter(uniswapRouter).swapExactTokensForTokens(
      IERC20(_asset).balanceOf(address(this)),
      0,
      path,
      mapleToken,
      block.timestamp + 1
    );
    IMapleToken(mapleToken).updateFundsReceived();
    emit ERC20Conversion(
      _asset,
      msg.sender,
      returnAmounts[0],
      returnAmounts[1]
    );
  }

  /**
   TODO:  Implement price oracle to ensure best quality execution (1% slippage) ...
          and also to prevent front-running of transactions.
          The price feed should be used for USDC conversion, supplied in the ...
          2nd parameter of the swapETHForExactTokens() function.
  */

  /// @notice Convert ETH through Uniswap via bilateral transaction (two asset path).
  function convertETH(uint256 _amountOut, uint256 _amountIn) isGovernor public {
    address[] memory path = new address[](2);
    path[0] = IUniswapRouter(uniswapRouter).WETH();
    path[1] = fundsToken;
    uint256[] memory returnAmounts = IUniswapRouter(uniswapRouter).swapETHForExactTokens{value: _amountIn}(
      _amountOut,
      path,
      mapleToken,
      block.timestamp + 1
    );
    IMapleToken(mapleToken).updateFundsReceived();
    emit ETHConversion(
      msg.sender,
      returnAmounts[0],
      returnAmounts[1]
    );
  }

}
