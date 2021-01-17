// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "./interfaces/ILoan.sol";

contract DebtLocker {

    using SafeMath for uint256;

    uint256 constant WAD = 10 ** 18;

    ILoan public immutable loan;        // The Loan that this locker is holding tokens for.
    IERC20 public immutable loanAsset;  // The loanAsset that this locker will claim.
    address public immutable owner;     // The owner of this Locker (a liquidity pool).

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
        loan      = ILoan(_loan);
        owner     = _owner;
        loanAsset = IERC20(ILoan(_loan).loanAsset());
    }

    /**
        @dev    Claim funds distribution for loan via ERC-2222.
        @return [0] = Total Claimed
                [1] = Interest Claimed
                [2] = Principal Claimed
                [3] = Fee Claimed
                [4] = Excess Returned Claimed
                [5] = TODO: Liquidation Amount Claimed Accounting
    */
    function claim() external isOwner returns(uint[5] memory) {

        // Tick FDT via ERC2222.
        loan.updateFundsReceived();

        // Calculate deltas.
        uint256 newInterest  = loan.interestPaid() - interestPaid;
        uint256 newPrincipal = loan.principalPaid() - principalPaid;
        uint256 newFee       = loan.feePaid() - feePaid;
        uint256 newExcess    = loan.excessReturned() - excessReturned;

        // Update accounting.
        interestPaid   = loan.interestPaid();
        principalPaid  = loan.principalPaid();
        feePaid        = loan.feePaid();
        excessReturned = loan.excessReturned();

        // Withdraw funds via ERC2222.
        loan.withdrawFunds();

        // Calculate distributed amounts, transfer the asset, and return metadata.
        uint256 sum       = newInterest.add(newPrincipal).add(newFee).add(newExcess);
        uint256 balance   = loanAsset.balanceOf(address(this));
        uint256 interest  = newInterest .mul(WAD).div(sum).mul(balance).div(WAD);
        uint256 principal = newPrincipal.mul(WAD).div(sum).mul(balance).div(WAD);
        uint256 fee       = newFee      .mul(WAD).div(sum).mul(balance).div(WAD);
        uint256 excess    = newExcess   .mul(WAD).div(sum).mul(balance).div(WAD);
        
        require(loanAsset.transfer(owner, balance), "DebtLocker::claim:ERR_XFER");

        return([balance, interest, principal, fee, excess]);
    }

}
