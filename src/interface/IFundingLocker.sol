// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

interface IFundingLocker {
    function fundingAsset() external view returns (address);

    function loanVault() external view returns (address);

    function pull(address, uint256) external returns (bool);

    function drain() external returns (bool);
}
