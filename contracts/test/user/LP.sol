// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "../../interfaces/IPool.sol";

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract LP {

    /************************/
    /*** DIRECT FUNCTIONS ***/
    /************************/

    function approve(address token, address who, uint256 amt) external {
        IERC20(token).approve(who, amt);
    }

    function withdraw(address pool, uint256 amt) external {
        IPool(pool).withdraw(amt);
    }

    function deposit(address pool, uint256 amt) external {
        IPool(pool).deposit(amt);
    }

    function transferFDT(address pool, address who, uint256 amt) external {
        IPool(pool).transfer(who, amt);
    }

    function claim(address pool, address loan, address dlFactory) external { IPool(pool).claim(loan, dlFactory); }

    function intendToWithdraw(address pool) external { IPool(pool).intendToWithdraw(); }

    /*********************/
    /*** TRY FUNCTIONS ***/
    /*********************/

    function try_deposit(address pool1, uint256 amt)  external returns (bool ok) {
        string memory sig = "deposit(uint256)";
        (ok,) = address(pool1).call(abi.encodeWithSignature(sig, amt));
    }

    function try_withdraw(address pool, uint256 amt) external returns(bool ok) {
        string memory sig = "withdraw(uint256)";
        (ok,) = pool.call(abi.encodeWithSignature(sig, amt));
    }

    function try_withdrawFunds(address pool) external returns(bool ok) {
        string memory sig = "withdrawFunds()";
        (ok,) = pool.call(abi.encodeWithSignature(sig));
    }

    function try_claim(address pool, address loan, address dlFactory) external returns (bool ok) {
        string memory sig = "claim(address,address)";
        (ok,) = pool.call(abi.encodeWithSignature(sig, loan, dlFactory));
    }

    function try_intendToWithdraw(address pool) external returns (bool ok) {
        string memory sig = "intendToWithdraw()";
        (ok,) = pool.call(abi.encodeWithSignature(sig));
    }

    function try_cancelWithdraw(address pool) external returns (bool ok) {
        string memory sig = "cancelWithdraw()";
        (ok,) = pool.call(abi.encodeWithSignature(sig));
    }

    function try_transfer(address pool, address who, uint256 amt) external returns (bool ok) {
        string memory sig = "transfer(address,uint256)";
        (ok,) = pool.call(abi.encodeWithSignature(sig, who, amt));
    }
}
