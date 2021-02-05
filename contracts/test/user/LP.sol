// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "../interfaces/IBPool.sol";

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract LP {

    /************************/
    /*** DIRECT FUNCTIONS ***/
    /************************/

    function approve(address token, address who, uint256 amt) external {
        IERC20(token).approve(who, amt);
    }

    function withdraw(address pool, uint256 amt) external {
        Pool(pool).withdraw(amt);
    }

    function deposit(address pool, uint256 amt) external {
        Pool(pool).deposit(amt);
    }


    /*********************/
    /*** TRY FUNCTIONS ***/
    /*********************/
    
}