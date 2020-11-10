pragma solidity 0.7.0;

contract MapleTreasury {

	address public mapleGlobals;
	address public mapleToken;

  constructor(address _mapleGlobals, address _mapleToken)  {
    mapleGlobals = _mapleGlobals;
    mapleToken = _mapleToken;
  }

}
