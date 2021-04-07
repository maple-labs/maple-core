// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

interface ICollateralLocker {
    function collateralAsset() external view returns (address);

    function loanVault() external view returns (address);

    function pull(address, uint256) external;
}
