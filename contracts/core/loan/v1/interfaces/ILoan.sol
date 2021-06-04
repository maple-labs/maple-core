// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "./ILoanFDT.sol";

interface ILoan is ILoanFDT {

    // State Variables
    function liquidityAsset() external view returns (address);

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

    function collateralRequiredForDrawdown(uint256) external view returns (uint256);


    // Loan Specifications
    function apr() external view returns (uint256);

    function paymentsRemaining() external view returns (uint256);

    function paymentIntervalSeconds() external view returns (uint256);

    function requestAmount() external view returns (uint256);

    function collateralRatio() external view returns (uint256);

    function fundingPeriod() external view returns (uint256);

    function defaultGracePeriod() external view returns (uint256);

    function createdAt() external view returns (uint256);

    function principalOwed() external view returns (uint256);

    function principalPaid() external view returns (uint256);

    function interestPaid() external view returns (uint256);

    function feePaid() external view returns (uint256);

    function excessReturned() external view returns (uint256);

    function getNextPayment() external view returns (uint256, uint256, uint256, uint256);

    function superFactory() external view returns (address);

    function termDays() external view returns (uint256);

    function nextPaymentDue() external view returns (uint256);

    function getFullPayment() external view returns (uint256, uint256, uint256);


    // Liquidations
    function amountLiquidated() external view returns (uint256);

    function defaultSuffered() external view returns (uint256);

    function amountRecovered() external view returns (uint256);

    function getExpectedAmountRecovered() external view returns (uint256);

    function liquidationExcess() external view returns (uint256);


    // Functions
    function fundLoan(address, uint256) external;

    function makePayment() external;

    function drawdown(uint256) external;

    function makeFullPayment() external;

    function triggerDefault() external;

    function unwind() external;


    // Security
    function pause() external;

    function unpause() external;

    function loanAdmins(address) external view returns (address);

    function setLoanAdmin(address, bool) external;


    // Misc
    function reclaimERC20(address) external;

}
