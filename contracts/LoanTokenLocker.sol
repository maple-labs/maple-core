// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./interfaces/ILoanVault.sol";

contract LoanTokenLocker {

    address public immutable vault; // The LoanVault that this locker is holding tokens for.
    address public immutable owner; // The owner of this Locker (a liquidity pool).

    // Struct for tracking investments.
    struct ClaimDifferential {
        address loanVaultFunded;
        address loanTokenLocker;
        uint256 amountFunded;
        uint256 principalPaid;
        uint256 interestPaid;
        uint256 feePaid;
        uint256 excessReturned;
        // TODO: uint256 liquidationClaimed;
    }

    constructor(address _vault, address _owner) public {
        loanToken = _vault;
        owner = _owner;
    }

    function claim() public {
        ILoanVault vault = ILoanVault(loanToken);
        vault.updateFundsReceived();
        vault.withdrawFunds();
    }

    modifier isOwner() {
        require(msg.sender == owner, "LoanTokenLocker:ERR_MSG_SENDER_NOT_OWNER");
        _;
    }

    function fetch() external isOwner {
        IERC20(loanToken).transfer(owner, IERC20(loanToken).balanceOf(address(this)));
    }
}
