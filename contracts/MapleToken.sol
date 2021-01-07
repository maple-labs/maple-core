// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "./token/FundsDistributionToken.sol";

contract MapleToken is FundsDistributionToken {

	modifier onlyFundsToken () {
		require(msg.sender == address(fundsToken), "FDT_ERC20Extension.onlyFundsToken: UNAUTHORIZED_SENDER");
		_;
	}

	constructor (
		string memory name, 
		string memory symbol,
		address fundsToken
	)  
		FundsDistributionToken(name, symbol, fundsToken)
		public 
	{
		require(address(fundsToken) != address(0), "FDT_ERC20Extension: INVALID_FUNDS_TOKEN_ADDRESS");
        _mint(msg.sender, 10000000 * (10 ** uint256(decimals())));
	}
}
