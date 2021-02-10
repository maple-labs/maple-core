// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "../../Loan.sol";

import "../../interfaces/IStakeLocker.sol";
import "../../interfaces/ILoan.sol";
import "../../interfaces/ILoanFactory.sol";

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract Borrower {

    /************************/
    /*** DIRECT FUNCTIONS ***/
    /************************/
    
    function makePayment(address loan) external {
        ILoan(loan).makePayment();
    }

    function makeFullPayment(address loan) external {
        ILoan(loan).makeFullPayment();
    }

    function drawdown(address loan, uint256 _drawdownAmount) external {
        ILoan(loan).drawdown(_drawdownAmount);
    }

    function approve(address token, address who, uint256 amt) external {
        IERC20(token).approve(who, amt);
    }

    function createLoan(
        address loanFactory,
        address loanAsset, 
        address collateralAsset, 
        address flFactory,
        address clFactory,
        uint256[6] memory specs,
        address[3] memory calcs
    ) 
        external returns (Loan loan) 
    {
        loan = Loan(
            ILoanFactory(loanFactory).createLoan(loanAsset, collateralAsset, flFactory, clFactory, specs, calcs)
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
        address loanAsset,
        address collateralAsset,
        address flFactory,
        address clFactory,
        uint256[6] memory specs,
        address[3] memory calcs
    ) 
        external returns (bool ok) 
    {
        string memory sig = "createLoan(address,address,address,address,uint256[6],address[3])";
        (ok,) = address(loanFactory).call(
            abi.encodeWithSignature(sig, loanAsset, collateralAsset, flFactory, clFactory, specs, calcs)
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

    function try_unwind(address loan) external returns (bool ok) {
        string memory sig = "unwind()";
        (ok,) = address(loan).call(abi.encodeWithSignature(sig));
    }

}