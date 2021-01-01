// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "./interfaces/ILoanVault.sol";

contract LoanTokenLocker {

    using SafeMath for uint256;

    address public immutable vault; // The LoanVault that this locker is holding tokens for.
    address public immutable owner; // The owner of this Locker (a liquidity pool).
    address public immutable asset; // The asset that this locker will claim.

    address public loanVaultFunded;
    uint256 public principalPaid;
    uint256 public interestPaid;
    uint256 public feePaid;
    uint256 public excessReturned;
    // TODO: uint256 liquidationClaimed;

    event Debug(string, uint);
    event DebugAdd(string, address);
    
    modifier isOwner() {
        emit DebugAdd("msg.sender", msg.sender);
        emit DebugAdd("owner", owner);
        require(msg.sender == owner, "LoanTokenLocker:ERR_MSG_SENDER_NOT_OWNER");
        _;
    }

    constructor(address _vault, address _owner) public {
        vault = _vault;
        owner = _owner;
        asset = ILoanVault(_vault).assetRequested();
        loanVaultFunded = _vault;
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

        emit Debug("newInterest", newInterest);
        emit Debug("newPrincipal", newPrincipal);
        emit Debug("newFee", newFee);
        emit Debug("newExcess", newExcess);

        // Update loans data structure.
        interestPaid   = loanVault.interestPaid();
        principalPaid  = loanVault.principalPaid();
        feePaid        = loanVault.feePaid();
        excessReturned = loanVault.excessReturned();

        // Update ERC2222 internal accounting for LoanVault.
        loanVault.withdrawFunds();

        uint256 sum       = newInterest.add(newPrincipal).add(newFee).add(newExcess);
        uint256 balance   = IERC20(asset).balanceOf(address(this));
        uint256 interest  = newInterest .mul(1 ether).div(sum).mul(balance).div(1 ether);
        uint256 principal = newPrincipal.mul(1 ether).div(sum).mul(balance).div(1 ether);
        uint256 fee       = newFee      .mul(1 ether).div(sum).mul(balance).div(1 ether);
        uint256 excess    = newExcess   .mul(1 ether).div(sum).mul(balance).div(1 ether);

        require(IERC20(asset).transfer(owner, balance), "LoanTokenLocker::claim:ERR_XFER");
        
        emit Debug("sum", sum);
        emit Debug("sum2", balance + interest + principal + fee + excess);
        emit Debug("balance", balance);
        emit Debug("interest", interest);
        emit Debug("principal", principal);
        emit Debug("fee", fee);
        emit Debug("excess", excess);

        return([balance, interest, principal, fee, excess]);
    }

}
