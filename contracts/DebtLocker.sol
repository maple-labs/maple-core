// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

import "./interfaces/ILoan.sol";

import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/SafeERC20.sol";

/// @title DebtLocker holds custody of LoanFDT tokens.
contract DebtLocker {

    using SafeMath  for uint256;
    using SafeERC20 for IERC20;

    uint256 constant WAD = 10 ** 18;

    ILoan   public immutable loan;       // The Loan that this locker is holding tokens for
    IERC20  public immutable loanAsset;  // The loanAsset that this locker will claim
    address public immutable owner;      // The owner of this Locker (the Pool)

    uint256 public principalPaid;    // Loan total principal   paid at time of claim()
    uint256 public interestPaid;     // Loan total interest    paid at time of claim()
    uint256 public feePaid;          // Loan total fees        paid at time of claim()
    uint256 public excessReturned;   // Loan total excess  returned at time of claim()
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
        return newAmt.mul(totalClaim).div(totalNewAmt);
    }

    /**
        @dev    Claim funds distribution for Loan via FDT.
        @return [0] = Total Claimed
                [1] = Interest Claimed
                [2] = Principal Claimed
                [3] = Fee Claimed
                [4] = Excess Returned Claimed
                [5] = Amount Recovered (from Liquidation)
                [6] = Default Suffered
    */
    function claim() external isOwner returns(uint256[7] memory) {

        // Initialize newDefaultSuffered as zero
        uint256 newDefaultSuffered = uint256(0);

        // Avoid stack too deep
        uint256 loan_defaultSuffered = loan.defaultSuffered();
    
        // If a default has occured, update storage variable and update memory variable from zero for return
        if (defaultSuffered == uint256(0) && loan_defaultSuffered > 0) {
            newDefaultSuffered = defaultSuffered = calcAllotment(loan.balanceOf(address(this)), loan.totalSupply(), loan_defaultSuffered);
        }
        
        // Account for any transfers into Loan that have occured since last call
        loan.updateFundsReceived();

        if(loan.withdrawableFundsOf(address(this)) > uint256(0)) {

            // Calculate payment deltas
            uint256 newInterest  = loan.interestPaid() - interestPaid;
            uint256 newPrincipal = loan.principalPaid() - principalPaid;

            // Update payments accounting
            interestPaid  = loan.interestPaid();
            principalPaid = loan.principalPaid();

            // Calculate one-time deltas
            uint256 newFee             = feePaid         > uint256(0) ? uint256(0) : loan.feePaid();
            uint256 newExcess          = excessReturned  > uint256(0) ? uint256(0) : loan.excessReturned();
            uint256 newAmountRecovered = amountRecovered > uint256(0) ? uint256(0) : loan.amountRecovered();

            // Update one-time accounting
            if(newFee > 0)             feePaid         = loan.feePaid();
            if(newExcess > 0)          excessReturned  = loan.excessReturned();
            if(newAmountRecovered > 0) amountRecovered = loan.amountRecovered();

            // Withdraw funds via FDT
            uint256 beforeBal = loanAsset.balanceOf(address(this));  // Current balance of locker (accounts for direct inflows)
            loan.withdrawFunds();                                    // Transfer funds from loan to debtLocker
            
            uint256 claimBal = loanAsset.balanceOf(address(this)).sub(beforeBal);  // Amount claimed from loan using FDT
            
            // Calculate distributed amounts, transfer the asset, and return metadata
            uint256 sum = newInterest.add(newPrincipal).add(newFee).add(newExcess).add(newAmountRecovered);

            // Calculate portions based on FDT claim
            newInterest  = calcAllotment(newInterest,  sum, claimBal);
            newPrincipal = calcAllotment(newPrincipal, sum, claimBal);

            newFee             = newFee             == uint256(0) ? uint256(0) : calcAllotment(newFee,             sum, claimBal);
            newExcess          = newExcess          == uint256(0) ? uint256(0) : calcAllotment(newExcess,          sum, claimBal);
            newAmountRecovered = newAmountRecovered == uint256(0) ? uint256(0) : calcAllotment(newAmountRecovered, sum, claimBal);

            loanAsset.safeTransfer(owner, claimBal);

            return([claimBal, newInterest, newPrincipal, newFee, newExcess, newAmountRecovered, newDefaultSuffered]);
        }

        return([0, 0, 0, 0, 0, 0, newDefaultSuffered]);
    }

    /**
        @dev Liquidate a loan that is held by this contract. Only called by the pool contract.
    */
    function triggerDefault() external isOwner {
        loan.triggerDefault();
    }
}
