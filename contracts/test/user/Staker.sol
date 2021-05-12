// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "../../interfaces/IBPool.sol";
import "../../interfaces/IStakeLocker.sol";

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract Staker {

    /************************/
    /*** DIRECT FUNCTIONS ***/
    /************************/

    function approve(address token, address account, uint256 amt) external {
        IERC20(token).approve(account, amt);
    }

    function increaseCustodyAllowance(address stakeLocker, address account, uint256 amt) public {
        IStakeLocker(stakeLocker).increaseCustodyAllowance(account, amt);
    }

    function stake(address stakeLocker, uint256 amt) external {
        IStakeLocker(stakeLocker).stake(amt);
    }

    function unstake(address stakeLocker, uint256 amt) external {
        IStakeLocker(stakeLocker).unstake(amt);
    }

    function transfer(address token, address dst, uint256 amt) external {
        IERC20(token).transfer(dst, amt);
    }

    function intendToUnstake(address stakeLocker) external { IStakeLocker(stakeLocker).intendToUnstake(); }

    // Balancer Pool
    function joinBPool(IBPool bPool, uint poolAmountOut, uint[] calldata maxAmountsIn) external {
        bPool.joinPool(poolAmountOut, maxAmountsIn);
    }



    /*********************/
    /*** TRY FUNCTIONS ***/
    /*********************/

    function try_stake(address stakeLocker, uint256 amt) external returns (bool ok) {
        string memory sig = "stake(uint256)";
        (ok,) = address(stakeLocker).call(abi.encodeWithSignature(sig, amt));
    }

    function try_unstake(address stakeLocker, uint256 amt) external returns (bool ok) {
        string memory sig = "unstake(uint256)";
        (ok,) = address(stakeLocker).call(abi.encodeWithSignature(sig, amt));
    }

    function try_transfer(address token, address dst, uint256 amt) external returns (bool ok) {
        string memory sig = "transfer(address,uint256)";
        (ok,) = address(token).call(abi.encodeWithSignature(sig, dst, amt));
    }

    function try_transferFrom(address token, address from, address to, uint256 amt) external returns (bool ok) {
        string memory sig = "transferFrom(address,address,uint256)";
        (ok,) = address(token).call(abi.encodeWithSignature(sig, from, to, amt));
    }

    function try_intendToUnstake(address stakeLocker) external returns (bool ok) {
        string memory sig = "intendToUnstake()";
        (ok,) = stakeLocker.call(abi.encodeWithSignature(sig));
    }

    function try_cancelUnstake(address stakeLocker) external returns (bool ok) {
        string memory sig = "cancelUnstake()";
        (ok,) = stakeLocker.call(abi.encodeWithSignature(sig));
    }

    function try_withdrawFunds(address stakeLocker) external returns (bool ok) {
        string memory sig = "withdrawFunds()";
        (ok,) = stakeLocker.call(abi.encodeWithSignature(sig));
    }

    function try_increaseCustodyAllowance(address stakeLocker, address account, uint256 amt) external returns (bool ok) {
        string memory sig = "increaseCustodyAllowance(address,uint256)";
        (ok,) = stakeLocker.call(abi.encodeWithSignature(sig, account, amt));
    }
}
