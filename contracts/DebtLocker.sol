// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "./interfaces/ILoan.sol";

contract DebtLocker {

    using SafeMath for uint256;

    address public immutable loan;       // The Loan that this locker is holding tokens for.
    address public immutable owner;      // The owner of this Locker (a liquidity pool).
    address public immutable loanAsset;  // The loanAsset that this locker will claim.

    uint256 public principalPaid;   // Vault total principal paid  at time of claim()
    uint256 public interestPaid;    // Vault total interest  paid  at time of claim()
    uint256 public feePaid;         // Vault total fees      paid  at time of claim()
    uint256 public excessReturned;  // Vault total excess returned at time of claim()
    // TODO: uint256 liquidationClaimed;
    
    modifier isOwner() {
        require(msg.sender == owner, "DebtLocker:ERR_MSG_SENDER_NOT_OWNER");
        _;
    }

    constructor(address _loan, address _owner) public {
        loan      = _loan;
        owner     = _owner;
        loanAsset = ILoan(_loan).loanAsset();
    }

    // Claim funds distribution via ERC-2222.
    // Returns: uint[0] = Total Claim
    //          uint[1] = Interest Claim
    //          uint[2] = Principal Claim
    //          uint[3] = Fee Claim
    //          uint[4] = Excess Returned Claim
    function claim() external isOwner returns(uint[5] memory) {

        // Create interface for Loan.
        ILoan ILoan = ILoan(loan);
        ILoan.updateFundsReceived();

        // Calculate deltas, or "net new" values.
        uint256 newInterest  = ILoan.interestPaid() - interestPaid;
        uint256 newPrincipal = ILoan.principalPaid() - principalPaid;
        uint256 newFee       = ILoan.feePaid() - feePaid;
        uint256 newExcess    = ILoan.excessReturned() - excessReturned;

        // Update loans data structure.
        interestPaid   = ILoan.interestPaid();
        principalPaid  = ILoan.principalPaid();
        feePaid        = ILoan.feePaid();
        excessReturned = ILoan.excessReturned();

        // Update ERC2222 internal accounting for Loan.
        ILoan.withdrawFunds();

        uint256 sum       = newInterest.add(newPrincipal).add(newFee).add(newExcess);
        uint256 balance   = IERC20(loanAsset).balanceOf(address(this));
        uint256 interest  = newInterest .mul(1 ether).div(sum).mul(balance).div(1 ether);
        uint256 principal = newPrincipal.mul(1 ether).div(sum).mul(balance).div(1 ether);
        uint256 fee       = newFee      .mul(1 ether).div(sum).mul(balance).div(1 ether);
        uint256 excess    = newExcess   .mul(1 ether).div(sum).mul(balance).div(1 ether);

        require(ILoan.transfer(owner, balance), "DebtLocker::claim:ERR_XFER");

        return([balance, interest, principal, fee, excess]);
    }

}
