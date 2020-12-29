// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

interface ILoanVault {
    
    // State Variables
    function fundsTokenBalance() external view returns (uint256);
    function assetRequested() external view returns (address);
    function assetCollateral() external view returns (address);
    function fundingLocker() external view returns (address);
    function fundingLockerFactory() external view returns (address);
    function collateralLocker() external view returns (address);
    function collateralLockerFactory() external view returns (address);
    function borrower() external view returns (address);
    function repaymentCalculator() external view returns (address);
    function premiumCalculator() external view returns (address);
    function loanState() external view returns (uint256);

    // Loan Specifications
    function aprBips() external view returns (uint256);
    function numberOfPayments() external view returns (uint256);
    function paymentIntervalSeconds() external view returns (uint256);
    function minRaise() external view returns (uint256);
    function collateralBipsRatio() external view returns (uint256);
    function fundingPeriodSeconds() external view returns (uint256);
    function loanCreatedTimestamp() external view returns (uint256);
    function principalOwed() external view returns (uint256);
    function drawdownAmount() external view returns (uint256);
    function principalPaid() external view returns (uint256);
    function interestPaid() external view returns (uint256);
    function getNextPayment() external view returns(uint256, uint256, uint256, uint256);
    
    // Functions
    function fundLoan(uint256, address) external;
    function updateFundsReceived() external;
    function withdrawFunds() external;
}
