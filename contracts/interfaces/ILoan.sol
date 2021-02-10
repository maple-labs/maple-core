// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface ILoan is IERC20 {
    
    // State Variables
    function fundsTokenBalance() external view returns (uint256);
    function loanAsset() external view returns (address);
    function collateralAsset() external view returns (address);
    function fundingLocker() external view returns (address);
    function flFactory() external view returns (address);
    function collateralLocker() external view returns (address);
    function clFactory() external view returns (address);
    function borrower() external view returns (address);
    function repaymentCalc() external view returns (address);
    function lateFeeCalc() external view returns (address);
    function premiumCalc() external view returns (address);
    function loanState() external view returns (uint256);
    function globals() external view returns (address);
    function collateralRequiredForDrawdown(uint256) external view returns(uint256);

    // Loan Specifications
    function apr() external view returns (uint256);
    function paymentsRemaining() external view returns (uint256);
    function paymentIntervalSeconds() external view returns (uint256);
    function requestAmount() external view returns (uint256);
    function collateralRatio() external view returns (uint256);
    function fundingPeriodSeconds() external view returns (uint256);
    function createdAt() external view returns (uint256);
    function principalOwed() external view returns (uint256);
    function drawdownAmount() external view returns (uint256);
    function principalPaid() external view returns (uint256);
    function interestPaid() external view returns (uint256);
    function feePaid() external view returns (uint256);
    function excessReturned() external view returns (uint256);
    function getNextPayment() external view returns (uint256, uint256, uint256, uint256);
    function superFactory() external view returns (address);
    function termDays() external view returns (uint256);
    function nextPaymentDue() external view returns (uint256);

    // Liquidations
    function defaultSuffered() external view returns (uint256);
    function amountRecovered() external view returns (uint256);
    function getAmountOfLoanAssetSwappedWithCollateral() external view returns(uint256);

    // Functions
    function fundLoan(uint256, address) external;
    function makePayment() external;
    function drawdown(uint256) external;
    function makeFullPayment() external;
    function triggerDefault() external;
    function unwind() external;

    // TODO: Create IFDT.sol (IFDT, inherit here and other places)
    function updateFundsReceived() external;
    function withdrawFunds() external;
}
