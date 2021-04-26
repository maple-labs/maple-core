// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

interface IDebtLocker {
    function loan() external view returns (address);

    function liquidityAsset() external view returns (address);

    function pool() external view returns (address);

    function lastPrincipalPaid() external view returns (uint256);

    function lastInterestPaid() external view returns (uint256);

    function lastFeePaid() external view returns (uint256);

    function lastExcessReturned() external view returns (uint256);

    function lastDefaultSuffered() external view returns (uint256);

    function lastAmountRecovered() external view returns (uint256);

    function claim() external returns(uint256[7] memory);
    
    function triggerDefault() external;
}
