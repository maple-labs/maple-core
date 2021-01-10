// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "./token/FDT.sol";

contract MapleToken is FDT {

		modifier onlyFundsToken () {
				require(
						msg.sender == address(fundsToken), 
						"FDT_ERC20Extension.onlyFundsToken: UNAUTHORIZED_SENDER"
				);
				_;
		}

		/**
				@notice Instanties the MapleToken.
        @param  name   		 Name of the token.
        @param  symbol 		 Symbol of the token.
        @param  fundsToken The asset claimable / distributed via ERC-2222, deposited to MapleToken contract.
    */
		constructor (
				string memory name, 
				string memory symbol, 
				address fundsToken
		) FDT(name, symbol, fundsToken) public {
				require(address(fundsToken) != address(0), "FDT_ERC20Extension: INVALID_FUNDS_TOKEN_ADDRESS");
				_mint(msg.sender, 10000000 * (10 ** uint256(decimals())));
		}
}
