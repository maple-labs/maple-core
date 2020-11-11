pragma solidity 0.7.0;

contract MapleTreasury {

	address public mapleGlobals;
	address public mapleToken;
  address public fundsToken;
  address public uniswapRouter;

  constructor(
    address _mapleGlobals, 
    address _mapleToken, 
    address _fundsToken, 
    address _uniswapRouter
  ) {
    mapleGlobals = _mapleGlobals;
    mapleToken = _mapleToken;
    fundsToken = _fundsToken;
    uniswapRouter = _uniswapRouter;
  }

  event ERC20Conversion(
    address _asset,
    address _by,
    uint _amountIn,
    uint _amountOut
  );

  event ETHConversion(
    address _by,
    uint _amountIn,
    uint _amountOut
  );

  // TODO:  Implement price oracle to ensure best quality execution (1% slippage) ...
  //        and also to prevent front-running of transactions.
  //        The price feed should be used for USDC conversion, supplied in the ...
  //        2nd parameter of the swapExactTokensForTokens() function.

  function convertERC20Bilateral(address _asset) public {
    require(
      ERC20(_asset).approve(uniswapRouter, ERC20(_asset).balanceOf(address(this))), 
      "MapleTreasury::convertERC20_ROUTER_APPROVE_FAIL"
    );
    address[] memory path = new address[](2);
    path[0] = _asset;
    path[1] = fundsToken;
    uint[] memory returnAmounts = IUniswapRouter(uniswapRouter).swapExactTokensForTokens(
      ERC20(_asset).balanceOf(address(this)),
      0,
      path,
      mapleToken,
      block.timestamp
    );
    emit ERC20Conversion(
      _asset,
      msg.sender,
      returnAmounts[0],
      returnAmounts[1]
    );
  }

  // TODO:  Implement price oracle to ensure best quality execution (1% slippage) ...
  //        and also to prevent front-running of transactions.
  //        The price feed should be used for USDC conversion, supplied in the ...
  //        2nd parameter of the swapExactTokensForTokens() function.

  function convertERC20Triangular(address _asset, address _triangularAsset) public {
    require(
      ERC20(_asset).approve(uniswapRouter, ERC20(_asset).balanceOf(address(this))), 
      "MapleTreasury::convertERC20_ROUTER_APPROVE_FAIL"
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
    emit ERC20Conversion(
      _asset,
      msg.sender,
      returnAmounts[0],
      returnAmounts[2]
    );
  }

  // TODO:  Implement price oracle to ensure best quality execution (1% slippage) ...
  //        and also to prevent front-running of transactions.
  //        The price feed should be used for USDC conversion, supplied in the ...
  //        2nd parameter of the swapETHForExactTokens() function.

  function convertETHBilateral() public {
    address[] memory path = new address[](2);
    path[0] = IUniswapRouter(uniswapRouter).WETH();
    path[1] = fundsToken;
    uint[] memory returnAmounts = IUniswapRouter(uniswapRouter).swapETHForExactTokens(
      0,
      path,
      mapleToken,
      block.timestamp
    );
    emit ETHConversion(
      msg.sender,
      returnAmounts[0],
      returnAmounts[1]
    );
  }

  // TODO:  Implement price oracle to ensure best quality execution (1% slippage) ...
  //        and also to prevent front-running of transactions.
  //        The price feed should be used for USDC conversion, supplied in the ...
  //        2nd parameter of the swapETHForExactTokens() function.

  function convertETHTriangular(address _triangularAsset) public {
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
    emit ETHConversion(
      msg.sender,
      returnAmounts[0],
      returnAmounts[2]
    );
  }

}

interface ERC20 {
  function balanceOf(address _owner) external view returns (uint256 balance);
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
