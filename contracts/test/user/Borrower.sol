// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "core/loan/v1/interfaces/ILoan.sol";
import "core/loan/v1/interfaces/ILoanFactory.sol";
import "core/stake-locker/v1/interfaces/IStakeLocker.sol";

contract Borrower {

    /************************/
    /*** DIRECT FUNCTIONS ***/
    /************************/

    function pause(address loan) external {
        ILoan(loan).pause();
    }

    function unpause(address loan) external {
        ILoan(loan).unpause();
    }

    function makePayment(address loan) external {
        ILoan(loan).makePayment();
    }

    function makeFullPayment(address loan) external {
        ILoan(loan).makeFullPayment();
    }

    function drawdown(address loan, uint256 _drawdownAmount) external {
        ILoan(loan).drawdown(_drawdownAmount);
    }

    function approve(address token, address account, uint256 amt) external {
        IERC20(token).approve(account, amt);
    }

    function createLoan(
        address loanFactory,
        address liquidityAsset,
        address collateralAsset,
        address flFactory,
        address clFactory,
        uint256[5] memory specs,
        address[3] memory calcs
    )
        external returns (ILoan loan)
    {
        loan = ILoan(
            ILoanFactory(loanFactory).createLoan(liquidityAsset, collateralAsset, flFactory, clFactory, specs, calcs)
        );
    }

    function triggerDefault(address loan) external {
        ILoan(loan).triggerDefault();
    }


    /*********************/
    /*** TRY FUNCTIONS ***/
    /*********************/

    function try_createLoan(
        address loanFactory,
        address liquidityAsset,
        address collateralAsset,
        address flFactory,
        address clFactory,
        uint256[5] memory specs,
        address[3] memory calcs
    )
        external returns (bool ok)
    {
        string memory sig = "createLoan(address,address,address,address,uint256[5],address[3])";
        (ok,) = address(loanFactory).call(
            abi.encodeWithSignature(sig, liquidityAsset, collateralAsset, flFactory, clFactory, specs, calcs)
        );
    }

    function try_drawdown(address loan, uint256 amt) external returns (bool ok) {
        string memory sig = "drawdown(uint256)";
        (ok,) = address(loan).call(abi.encodeWithSignature(sig, amt));
    }

    function try_makePayment(address loan) external returns (bool ok) {
        string memory sig = "makePayment()";
        (ok,) = address(loan).call(abi.encodeWithSignature(sig));
    }

    function try_makeFullPayment(address loan) external returns (bool ok) {
        string memory sig = "makeFullPayment()";
        (ok,) = address(loan).call(abi.encodeWithSignature(sig));
    }

    function try_unwind(address loan) external returns (bool ok) {
        string memory sig = "unwind()";
        (ok,) = address(loan).call(abi.encodeWithSignature(sig));
    }

    function try_pull(address locker, address dst, uint256 amt) external returns (bool ok) {
        string memory sig = "pull(address,uint256)";
        (ok,) = address(locker).call(abi.encodeWithSignature(sig, dst, amt));
    }

    function try_setLoanAdmin(address loan, address newLoanAdmin, bool status) external returns (bool ok) {
        string memory sig = "setLoanAdmin(address,bool)";
        (ok,) = address(loan).call(abi.encodeWithSignature(sig, newLoanAdmin, status));
    }

    function try_pause(address target) external returns (bool ok) {
        string memory sig = "pause()";
        (ok,) = target.call(abi.encodeWithSignature(sig));
    }

    function try_unpause(address target) external returns (bool ok) {
        string memory sig = "unpause()";
        (ok,) = target.call(abi.encodeWithSignature(sig));
    }
}
