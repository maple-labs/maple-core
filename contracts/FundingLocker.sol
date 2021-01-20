// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract FundingLocker {

    IERC20  public immutable loanAsset;  // Asset the Loan was funded with
    address public immutable loan;       // Loan this FundingLocker has funded

    constructor(address _loanAsset, address _loan) public {
        loanAsset = IERC20(_loanAsset);
        loan      = _loan;
    }

    modifier isLoan() {
        require(msg.sender == loan, "FundingLocker:MSG_SENDER_NOT_LOAN");
        _;
    }

    /**
        @dev Transfers _amount of loanAsset to dst.
        @param  dst Desintation to transfer loanAsset to.
        @param  amt Amount of loanAsset to transfer.
    */
    function pull(address dst, uint256 amt) isLoan public returns(bool) {
        return loanAsset.transfer(dst, amt);
    }

    /**
        @dev Transfers entire amount of loanAsset held in escrow to Loan.
    */
    function drain() isLoan public returns(bool) {
        uint256 amt = loanAsset.balanceOf(address(this));
        return loanAsset.transfer(loan, amt);
    }
    
}
