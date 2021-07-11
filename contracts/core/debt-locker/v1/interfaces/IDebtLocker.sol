// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "../../../loan/v1/interfaces/ILoan.sol";

/// @title DebtLocker holds custody of LoanFDT tokens.
interface IDebtLocker {

    /**
        @dev The Loan contract this locker is holding tokens for.
     */
    function loan() external view returns (ILoan);

    /**
        @dev The Liquidity Asset this locker can claim.
     */
    function liquidityAsset() external view returns (IERC20);

    /**
        @dev The owner of this Locker (the Pool).
     */
    function pool() external view returns (address);

    /**
        @dev The Loan total principal paid at last time `claim()` was called.
     */
    function lastPrincipalPaid() external view returns (uint256);

    /**
        @dev The Loan total interest paid at last time `claim()` was called.
     */
    function lastInterestPaid() external view returns (uint256);

    /**
        @dev The Loan total fees paid at last time `claim()` was called.
     */
    function lastFeePaid() external view returns (uint256);

    /**
        @dev The Loan total excess returned at last time `claim()` was called.
     */
    function lastExcessReturned() external view returns (uint256);

    /**
        @dev The Loan total default suffered at last time `claim()` was called.
     */
    function lastDefaultSuffered() external view returns (uint256);

    /**
        @dev Then Liquidity Asset (a.k.a. loan asset) recovered from liquidation of Loan collateral.
     */
    function lastAmountRecovered() external view returns (uint256);

    /**
        @dev    Claims funds distribution for Loan via LoanFDT. 
        @dev    Only the Pool can call this function. 
        @return [0] => Total Claimed.
                [1] => Interest Claimed.
                [2] => Principal Claimed.
                [3] => Pool Delegate Fee Claimed.
                [4] => Excess Returned Claimed.
                [5] => Amount Recovered (from Liquidation).
                [6] => Default Suffered.
     */
    function claim() external returns (uint256[7] memory);

    /**
        @dev Liquidates a Loan that is held by this contract. 
        @dev Only the Pool can call this function. 
     */
    function triggerDefault() external;

}
