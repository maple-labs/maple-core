// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

interface IDebtLocker {
    function pool() external returns (address);

    function liquidityAsset() external returns (address);

    function claim() external returns(uint256[7] memory);
    
    function triggerDefault() external;
}
