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
    address public immutable pool;       // The owner of this Locker (the Pool)

    uint256 public principalPaid;    // Loan total principal   paid at time of claim()
    uint256 public interestPaid;     // Loan total interest    paid at time of claim()
    uint256 public feePaid;          // Loan total fees        paid at time of claim()
    uint256 public excessReturned;   // Loan total excess  returned at time of claim()
    uint256 public defaultSuffered;  // Loan total default suffered at time of claim()
    uint256 public amountRecovered;  // Liquidity asset (a.k.a. loan asset) recovered from liquidation of Loan collateral
    
    modifier isPool() {
        require(msg.sender == pool, "DebtLocker:MSG_SENDER_NOT_POOL");
        _;
    }

    constructor(address _loan, address _pool) public {
        loan      = ILoan(_loan);
        pool      = _pool;
        loanAsset = IERC20(ILoan(_loan).loanAsset());
    }

    function calcAllotment(uint256 newAmt, uint256 totalClaim, uint256 totalNewAmt) internal pure returns (uint256) {
        return totalNewAmt > 0 ? newAmt.mul(totalClaim).div(totalNewAmt) : 0;
    }

    /**
        @dev    Claim funds distribution for Loan via FDT.
        @return [0] = Total Claimed
                [1] = Interest Claimed
                [2] = Principal Claimed
                [3] = Pool Delegate Fee Claimed
                [4] = Excess Returned Claimed
                [5] = Amount Recovered (from Liquidation)
                [6] = Default Suffered
    */
    function claim() external isPool returns(uint256[7] memory) {

        // Initialize newDefaultSuffered as zero
        uint256 newDefaultSuffered   = uint256(0);
        uint256 loan_defaultSuffered = loan.defaultSuffered();
    
        // If a default has occurred, update storage variable and update memory variable from zero for return.
        // `defaultSuffered` represents the proportional loss that the DebtLocker registers based on its balance
        // of LoanFDTs in comparison to the totalSupply of LoanFDTs.
        // Default will occur only once so below statement will only be `true` once.
        if (defaultSuffered == uint256(0) && loan_defaultSuffered > uint256(0)) {
            newDefaultSuffered = defaultSuffered = calcAllotment(loan.balanceOf(address(this)), loan_defaultSuffered, loan.totalSupply());
        }
        
        // Account for any transfers into Loan that have occurred since last call
        loan.updateFundsReceived();

        // If there are claimable funds, calculate portions and claim using LoanFDT
        if (loan.withdrawableFundsOf(address(this)) > uint256(0)) {

            // Calculate payment deltas
            uint256 newInterest  = loan.interestPaid() - interestPaid;    // `loan.interestPaid`  updated in `loan._makePayment()`
            uint256 newPrincipal = loan.principalPaid() - principalPaid;  // `loan.principalPaid` updated in `loan._makePayment()` 

            // Update storage variables for next delta calculation
            interestPaid  = loan.interestPaid();
            principalPaid = loan.principalPaid();

            // Calculate one-time deltas if storage variables have not yet been updated
            uint256 newFee             = feePaid         == uint256(0) ? loan.feePaid()         : uint256(0);  // `loan.feePaid`          updated in `loan.drawdown()` 
            uint256 newExcess          = excessReturned  == uint256(0) ? loan.excessReturned()  : uint256(0);  // `loan.excessReturned`   updated in `loan.unwind()` OR `loan.drawdown()` if `amt < fundingLockerBal`
            uint256 newAmountRecovered = amountRecovered == uint256(0) ? loan.amountRecovered() : uint256(0);  // `loan.amountRecovered`  updated in `loan.triggerDefault()`

            // Update DebtLocker storage variable if Loan storage variable has been updated since last claim
            if (newFee > 0)             feePaid         = newFee;
            if (newExcess > 0)          excessReturned  = newExcess;
            if (newAmountRecovered > 0) amountRecovered = newAmountRecovered;

            // Withdraw all claimable funds via LoanFDT
            uint256 beforeBal = loanAsset.balanceOf(address(this));                 // Current balance of DebtLocker (accounts for direct inflows)
            loan.withdrawFunds();                                                   // Transfer funds from Loan to DebtLocker
            uint256 claimBal  = loanAsset.balanceOf(address(this)).sub(beforeBal);  // Amount claimed from Loan using LoanFDT
            
            // Calculate sum of all deltas, to be used to calculate portions for metadata
            uint256 sum = newInterest.add(newPrincipal).add(newFee).add(newExcess).add(newAmountRecovered);

            // Calculate payment portions based on LoanFDT claim
            newInterest  = calcAllotment(newInterest,  claimBal, sum);
            newPrincipal = calcAllotment(newPrincipal, claimBal, sum);

            // Calculate one-time portions based on LoanFDT claim
            newFee             = newFee             == uint256(0) ? uint256(0) : calcAllotment(newFee,             claimBal, sum);
            newExcess          = newExcess          == uint256(0) ? uint256(0) : calcAllotment(newExcess,          claimBal, sum);
            newAmountRecovered = newAmountRecovered == uint256(0) ? uint256(0) : calcAllotment(newAmountRecovered, claimBal, sum);

            loanAsset.safeTransfer(pool, claimBal);  // Transfer entire amount claimed using LoanFDT

            // Return claim amount plus all relevant metadata, to be used by Pool for further claim logic
            // Note: newInterest + newPrincipal + newFee + newExcess + newAmountRecovered = claimBal - dust
            //       The dust on the right side of the equation gethers in the pool after transfers are made
            return([claimBal, newInterest, newPrincipal, newFee, newExcess, newAmountRecovered, newDefaultSuffered]);
        }
        
        // Handles case where no claimable funds are present but a default must be registered (zero-collateralized loans defaulting)
        return([0, 0, 0, 0, 0, 0, newDefaultSuffered]);
    }

    /**
        @dev Liquidate a loan that is held by this contract. Only called by the pool contract.
    */
    function triggerDefault() external isPool {
        loan.triggerDefault();
    }
}
