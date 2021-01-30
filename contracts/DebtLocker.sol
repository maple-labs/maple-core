// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "./interfaces/ILoan.sol";

contract DebtLocker {

    using SafeMath for uint256;

    uint256 constant WAD = 10 ** 18;

    ILoan   public immutable loan;       // The Loan that this locker is holding tokens for.
    IERC20  public immutable loanAsset;  // The loanAsset that this locker will claim.
    address public immutable owner;      // The owner of this Locker (a liquidity pool).

    uint256 public principalPaid;    // Loan total principal   paid at time of claim()
    uint256 public interestPaid;     // Loan total interest    paid at time of claim()
    uint256 public feePaid;          // Loan total fees        paid at time of claim()
    uint256 public excessReturned;   // Loan total excess  returned at time of claim()
    uint256 public defaultSuffered;  // Loan total default suffered at time of claim()
    uint256 public amountRecovered;  // Liquidity asset (a.k.a. loan asset) recovered from liquidation of Loan collateral
    
    modifier isOwner() {
        require(msg.sender == owner, "DebtLocker:MSG_SENDER_NOT_OWNER");
        _;
    }

    constructor(address _loan, address _owner) public {
        loan      = ILoan(_loan);
        owner     = _owner;
        loanAsset = IERC20(ILoan(_loan).loanAsset());
    }

    function calcAllotment(uint256 newAmt, uint256 totalNewAmt, uint256 totalClaim) internal pure returns (uint256) {
        return newAmt.mul(WAD).div(totalNewAmt).mul(totalClaim).div(WAD);
    }

    /**
        @dev    Claim funds distribution for loan via FDT.
        @return [0] = Total Claimed
                [1] = Interest Claimed
                [2] = Principal Claimed
                [3] = Fee Claimed
                [4] = Excess Returned Claimed
                [5] = Default Suffered
                [6] = Amount Recovered (from Liquidation)
    */
    function claim() external isOwner returns(uint256[7] memory) {

        // Tick FDT via FDT.
        loan.updateFundsReceived();

        // Calculate deltas.
        uint256 newInterest  = loan.interestPaid() - interestPaid;
        uint256 newPrincipal = loan.principalPaid() - principalPaid;
        uint256 newFee       = loan.feePaid() - feePaid;
        uint256 newExcess    = loan.excessReturned() - excessReturned;

        // Update accounting.
        interestPaid    = loan.interestPaid();
        principalPaid   = loan.principalPaid();
        feePaid         = loan.feePaid();
        excessReturned  = loan.excessReturned();

        // TODO: Improve this
        amountRecovered = loan.amountRecovered().mul(loan.balanceOf(address(this))).div(loan.totalSupply());

        // Update defaultSuffered value based on ratio of total supply of DebtTokens owned by this DebtLocker.
        defaultSuffered = loan.defaultSuffered().mul(loan.balanceOf(address(this))).div(loan.totalSupply());

        // Withdraw funds via FDT.
        uint256 beforeBal = loanAsset.balanceOf(address(this));  // Current balance of locker (accounts for direct inflows)
        loan.withdrawFunds();                                    // Transfer funds from loan to debtLocker
        uint256 afterBal = loanAsset.balanceOf(address(this));   // Balance of locker after claiming funds using FDT
        
        uint256 claimBal = afterBal.sub(beforeBal);  // Amount claimed from loan using FDT
        

        // Calculate distributed amounts, transfer the asset, and return metadata.
        uint256 sum       = newInterest.add(newPrincipal).add(newFee).add(newExcess);
        uint256 interest  = calcAllotment(newInterest,  sum, claimBal);
        uint256 principal = calcAllotment(newPrincipal, sum, claimBal);
        uint256 fee       = calcAllotment(newFee,       sum, claimBal);
        uint256 excess    = calcAllotment(newExcess,    sum, claimBal);

        require(loanAsset.transfer(owner, claimBal), "DebtLocker:CLAIM_TRANSFER");

        return([claimBal, interest, principal, fee, excess, defaultSuffered, amountRecovered]);
    }

}
