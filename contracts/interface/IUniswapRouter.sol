pragma solidity 0.7.0;

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