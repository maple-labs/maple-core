// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "core/loan/v1/interfaces/ILoan.sol";

contract Lender {

    /************************/
    /*** DIRECT FUNCTIONS ***/
    /************************/

    function fundLoan(address loan, uint256 amt, address account) external {
        ILoan(loan).fundLoan(account, amt);
    }

    function approve(address token, address account, uint256 amt) external {
        IERC20(token).approve(account, amt);
    }

    function transfer(address token, address account, uint256 amt) external {
        IERC20(token).transfer(account, amt);
    }

    function triggerDefault(address loan) public {
        ILoan(loan).triggerDefault();
    }

    function withdrawFunds(address loan) public {
        ILoan(loan).withdrawFunds();
    }


    /*********************/
    /*** TRY FUNCTIONS ***/
    /*********************/

    // To assert failures
    function try_drawdown(address loan, uint256 amt) external returns (bool ok) {
        string memory sig = "drawdown(uint256)";
        (ok,) = address(loan).call(abi.encodeWithSignature(sig, amt));
    }

    function try_fundLoan(address loan, address mintTo, uint256 amt) external returns (bool ok) {
        string memory sig = "fundLoan(address,uint256)";
        (ok,) = address(loan).call(abi.encodeWithSignature(sig, mintTo, amt));
    }

    function try_trigger_default(address loan) external returns (bool ok) {
        string memory sig = "triggerDefault()";
        (ok,) = loan.call(abi.encodeWithSignature(sig));
    }

    function try_withdrawFunds(address loan) external returns (bool ok) {
        string memory sig = "withdrawFunds()";
        (ok,) = loan.call(abi.encodeWithSignature(sig));
    }

    function try_triggerDefault(address loan) external returns (bool ok) {
        string memory sig = "triggerDefault()";
        (ok,) = address(loan).call(abi.encodeWithSignature(sig));
    }
}
