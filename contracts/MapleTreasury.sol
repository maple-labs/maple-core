pragma solidity 0.7.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
<<<<<<< HEAD
import "./interface/IGlobals.sol";
=======
>>>>>>> 4803460a07d87723973ecc20de74ab40d6fc3ee7

contract MapleTreasury {

	using SafeMath for uint256;

  /// @notice mapletoken is the MapleToken.sol contract.
  address public mapleToken;

  /// @notice fundsToken is the _fundsToken value in the MapleToken.sol contract.
  address public fundsToken;

  /// @notice uniswapRouter is the official UniswapV2 router contract.
  address public uniswapRouter;

<<<<<<< HEAD
  /// @notice mapleGlobals is the MapleGlobals.sol contract.
  address public mapleGlobals;

=======
>>>>>>> 4803460a07d87723973ecc20de74ab40d6fc3ee7
  /// @notice Instantiates the MapleTreasury contract.
  /// @param _mapleToken is the MapleToken.sol contract.
  /// @param _fundsToken is the _fundsToken value in the MapleToken.sol contract.
  /// @param _uniswapRouter is the official UniswapV2 router contract.
<<<<<<< HEAD
  /// @param _mapleGlobals is the MapleGlobals.sol contract.
  constructor(
    address _mapleToken, 
    address _fundsToken, 
    address _uniswapRouter,
    address _mapleGlobals
=======
  constructor(
    address _mapleToken, 
    address _fundsToken, 
    address _uniswapRouter
>>>>>>> 4803460a07d87723973ecc20de74ab40d6fc3ee7
  ) {
    mapleToken = _mapleToken;
    fundsToken = _fundsToken;
    uniswapRouter = _uniswapRouter;
<<<<<<< HEAD
    mapleGlobals = _mapleGlobals;
=======
>>>>>>> 4803460a07d87723973ecc20de74ab40d6fc3ee7
  }

  /// @notice Fired when an ERC-20 asset is converted to fundsToken and transferred to mapleToken.
  /// @param _asset The asset that is converted.
  /// @param _by The msg.sender calling the conversion function.
  /// @param _amountIn The amount of _asset converted to fundsToken.
  /// @param _amountOut The amount of fundsToken received for _asset conversion.
  event ERC20Conversion(
    address _asset,
    address _by,
    uint _amountIn,
    uint _amountOut
  );

  /// @notice Fired when ETH is converted to fundsToken and transferred to mapleToken.
  /// @param _by The msg.sender calling the conversion function.
  /// @param _amountIn The amount of ETH converted to fundsToken.
  /// @param _amountOut The amount of fundsToken received for ETH conversion.
  event ETHConversion(
    address _by,
    uint _amountIn,
    uint _amountOut
  );

  /// @notice Fired when fundsToken is passed through to mapleToken.
  event PassThrough(
    address _by,
    uint _amount
  );

<<<<<<< HEAD
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
=======
  /// @notice Passes through the current fundsToken to MapleToken.
  function passThroughFundsToken() public {
>>>>>>> 4803460a07d87723973ecc20de74ab40d6fc3ee7
    emit PassThrough(
      msg.sender,
      ERC20(fundsToken).balanceOf(address(this))
    );
    require(
      ERC20(fundsToken).transfer(mapleToken, ERC20(fundsToken).balanceOf(address(this))), 
<<<<<<< HEAD
      "MapleTreasury::passThroughFundsToken:FUNDS_RECEIVE_TRANSFER_ERROR"
=======
      "MapleTreasury::convertERC20Bilateral:FUNDS_RECEIVE_TRANSFER_ERROR"
>>>>>>> 4803460a07d87723973ecc20de74ab40d6fc3ee7
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
<<<<<<< HEAD
  function convertERC20(address _asset) isGovernor public {
    require(_asset != fundsToken, "MapleTreasury::convertERC20:ERR_ASSET");
    require(
      ERC20(_asset).approve(uniswapRouter, ERC20(_asset).balanceOf(address(this))), 
      "MapleTreasury::convertERC20:ROUTER_APPROVE_FAIL"
=======
  function convertERC20Bilateral(address _asset) public {
    require(_asset != fundsToken, "MapleTreasury::convertERC20Bilateral:ERR_ASSET");
    require(
      ERC20(_asset).approve(uniswapRouter, ERC20(_asset).balanceOf(address(this))), 
      "MapleTreasury::convertERC20Bilateral:ROUTER_APPROVE_FAIL"
>>>>>>> 4803460a07d87723973ecc20de74ab40d6fc3ee7
    );
    address[] memory path = new address[](2);
    path[0] = _asset;
    path[1] = fundsToken;
    uint[] memory returnAmounts = IUniswapRouter(uniswapRouter).swapExactTokensForTokens(
      ERC20(_asset).balanceOf(address(this)),
      0,
      path,
      mapleToken,
      block.timestamp + 1000
    );
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
<<<<<<< HEAD
=======
          2nd parameter of the swapExactTokensForTokens() function.
  */

  /// @notice Convert an ERC-20 asset through Uniswap via triangular transaction (three asset path).
  /// @param _asset The ERC-20 asset to convert.
  /// @param _triangularAsset The middle asset conversion path, _asset -> _triangularAsset -> fundsToken.
  function convertERC20Triangular(address _asset, address _triangularAsset) public {
    require(_asset != fundsToken, "MapleTreasury::convertERC20Bilateral:ERR_ASSET");
    require(_triangularAsset != fundsToken, "MapleTreasury::convertERC20Bilateral:ERR_ASSET");
    require(
      ERC20(_asset).approve(uniswapRouter, ERC20(_asset).balanceOf(address(this))), 
      "MapleTreasury::convertERC20Triangular:ROUTER_APPROVE_FAIL"
    );
    address[] memory path = new address[](3);
    path[0] = _asset;
    path[1] = _triangularAsset;
    path[2] = fundsToken;
    uint[] memory returnAmounts = IUniswapRouter(uniswapRouter).swapExactTokensForTokens(
      ERC20(_asset).balanceOf(address(this)),
      0,
      path,
      mapleToken,
      block.timestamp
    );
    require(
      ERC20(fundsToken).transfer(mapleToken, returnAmounts[2]), 
      "MapleTreasury::convertERC20Triangular:FUNDS_RECEIVE_TRANSFER_ERROR"
    );
    emit ERC20Conversion(
      _asset,
      msg.sender,
      returnAmounts[0],
      returnAmounts[2]
    );
  }

  /**
   TODO:  Implement price oracle to ensure best quality execution (1% slippage) ...
          and also to prevent front-running of transactions.
          The price feed should be used for USDC conversion, supplied in the ...
>>>>>>> 4803460a07d87723973ecc20de74ab40d6fc3ee7
          2nd parameter of the swapETHForExactTokens() function.
  */

  /// @notice Convert ETH through Uniswap via bilateral transaction (two asset path).
<<<<<<< HEAD
  function convertETH(uint _amountOut) isGovernor public {
=======
  function convertETHBilateral() public {
>>>>>>> 4803460a07d87723973ecc20de74ab40d6fc3ee7
    address[] memory path = new address[](2);
    path[0] = IUniswapRouter(uniswapRouter).WETH();
    path[1] = fundsToken;
    uint[] memory returnAmounts = IUniswapRouter(uniswapRouter).swapETHForExactTokens(
<<<<<<< HEAD
      _amountOut,
      path,
      mapleToken,
      block.timestamp + 1000
=======
      0,
      path,
      mapleToken,
      block.timestamp
    );
    require(
      ERC20(fundsToken).transfer(mapleToken, returnAmounts[2]), 
      "MapleTreasury::convertETHBilateral:FUNDS_RECEIVE_TRANSFER_ERROR"
>>>>>>> 4803460a07d87723973ecc20de74ab40d6fc3ee7
    );
    emit ETHConversion(
      msg.sender,
      returnAmounts[0],
      returnAmounts[1]
    );
  }

<<<<<<< HEAD
=======
  /**
   TODO:  Implement price oracle to ensure best quality execution (1% slippage) ...
          and also to prevent front-running of transactions.
          The price feed should be used for USDC conversion, supplied in the ...
          2nd parameter of the swapETHForExactTokens() function.
  */

  /// @notice Convert ETH through Uniswap via triangular transaction (three asset path).
  /// @param _triangularAsset The middle asset conversion path, ETH -> _triangularAsset -> fundsToken.
  function convertETHTriangular(address _triangularAsset) public {
    require(_triangularAsset != fundsToken, "MapleTreasury::convertERC20Bilateral:ERR_ASSET");
    address[] memory path = new address[](3);
    path[0] = IUniswapRouter(uniswapRouter).WETH();
    path[1] = _triangularAsset;
    path[2] = fundsToken;
    uint[] memory returnAmounts = IUniswapRouter(uniswapRouter).swapETHForExactTokens(
      0,
      path,
      mapleToken,
      block.timestamp
    );
    require(
      ERC20(fundsToken).transfer(mapleToken, returnAmounts[2]), 
      "MapleTreasury::convertETHTriangular:FUNDS_RECEIVE_TRANSFER_ERROR"
    );
    emit ETHConversion(
      msg.sender,
      returnAmounts[0],
      returnAmounts[2]
    );
  }

>>>>>>> 4803460a07d87723973ecc20de74ab40d6fc3ee7
}

interface ERC20 {
  function balanceOf(address _owner) external view returns (uint256 balance);
  function transfer(address _to, uint256 _value) external returns (bool success);
  function approve(address _spender, uint256 _value) external returns (bool success);
}

interface IUniswapRouter {

  function swapExactTokensForTokens(
    uint amountIn,
    uint amountOutMin,
    address[] calldata path,
    address to,
    uint deadline
  ) external returns (uint[] memory amounts);
  
  function swapETHForExactTokens(
    uint amountOut,
    address[] calldata path, 
    address to, 
    uint deadline
  ) external payable returns (uint[] memory amounts);

  function quote(
    uint amountA, 
    uint reserveA, 
    uint reserveB
  ) external pure returns (uint amountB);
  
  function WETH() external pure returns (address);

}
