// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "../../interfaces/IStakeLocker.sol";

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract Staker {

    /************************/
    /*** DIRECT FUNCTIONS ***/
    /************************/

    function approve(address token, address who, uint256 amt) external {
        IERC20(token).approve(who, amt);
    }

    function stake(address stakeLocker, uint256 amt) external {
        IStakeLocker(stakeLocker).stake(amt);
    }

    function unstake(address stakeLocker, uint256 amt) external {
        IStakeLocker(stakeLocker).unstake(amt);
    }


    /*********************/
    /*** TRY FUNCTIONS ***/
    /*********************/

    function try_stake(address stakeLocker, uint256 amt) external returns(bool ok) {
        string memory sig = "stake(uint256)";
        (ok,) = address(stakeLocker).call(abi.encodeWithSignature(sig, amt));
    }

    function try_unstake(address stakeLocker, uint256 amt) external returns(bool ok) {
        string memory sig = "unstake(uint256)";
        (ok,) = address(stakeLocker).call(abi.encodeWithSignature(sig, amt));
    }
    
}