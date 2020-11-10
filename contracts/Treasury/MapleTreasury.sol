pragma solidity 0.7.0;

import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';

contract MapleTreasury {

	address public mapleGlobals;
	address public mapleToken;

  constructor(address _mapleGlobals, address _mapleToken)  {
    mapleGlobals = _mapleGlobals;
    mapleToken = _mapleToken;
  }

}
