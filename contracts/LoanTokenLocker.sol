// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./math/math.sol";
import "./interfaces/ILoanVault.sol";

contract LoanTokenLocker is DSMath {

    address public immutable vault;  // The LoanVault that this locker is holding tokens for.
    address public immutable owner;  // The owner of this Locker (a liquidity pool).
    address public immutable asset;  // The asset that this locker will claim.

    uint256 public principalPaid;   // Vault total principal paid  at time of claim()
    uint256 public interestPaid;    // Vault total interest  paid  at time of claim()
    uint256 public feePaid;         // Vault total fees      paid  at time of claim()
    uint256 public excessReturned;  // Vault total excess returned at time of claim()
    // TODO: uint256 liquidationClaimed;
    
    modifier isOwner() {
        require(msg.sender == owner, "LoanTokenLocker:ERR_MSG_SENDER_NOT_OWNER");
        _;
    }

    constructor(address _vault, address _owner) public {
        vault = _vault;
        owner = _owner;
        asset = ILoanVault(_vault).assetRequested();
    }

    // Claim funds distribution via ERC-2222.
    // Returns: uint[0] = Total Claim
    //          uint[1] = Interest Claim
    //          uint[2] = Principal Claim
    //          uint[3] = Fee Claim
    //          uint[4] = Excess Returned Claim
    function claim() external isOwner returns(uint[5] memory) {

        // Create interface for LoanVault.
        ILoanVault loanVault = ILoanVault(vault);
        loanVault.updateFundsReceived();

        // Calculate deltas, or "net new" values.
        uint256 newInterest  = loanVault.interestPaid() - interestPaid;
        uint256 newPrincipal = loanVault.principalPaid() - principalPaid;
        uint256 newFee       = loanVault.feePaid() - feePaid;
        uint256 newExcess    = loanVault.excessReturned() - excessReturned;

        // Update loans data structure.
        interestPaid   = loanVault.interestPaid();
        principalPaid  = loanVault.principalPaid();
        feePaid        = loanVault.feePaid();
        excessReturned = loanVault.excessReturned();

        // Update ERC2222 internal accounting for LoanVault.
        loanVault.withdrawFunds();

        uint256 sum       = add(newInterest, add(newPrincipal, add(newFee, newExcess)));
        uint256 balance   = IERC20(asset).balanceOf(address(this));
        uint256 interest  = wmul(wdiv(newInterest,  sum), balance);
        uint256 principal = wmul(wdiv(newPrincipal, sum), balance);
        uint256 fee       = wmul(wdiv(newFee,       sum), balance);
        uint256 excess    = wmul(wdiv(newExcess,    sum), balance);

        require(IERC20(asset).transfer(owner, balance), "LoanTokenLocker::claim:ERR_XFER");

        return([balance, interest, principal, fee, excess]);
    }

}
