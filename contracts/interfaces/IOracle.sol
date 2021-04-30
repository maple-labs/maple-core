// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

interface IOracle {

    function priceFeed() external view returns (address);

    function globals() external view returns (address);

    function assetAddress() external view returns (address);

    function manualOverride() external view returns (bool);

    function manualPrice() external view returns (int256);

    function getLatestPrice() external view returns (int256);
    
    function changeAggregator(address) external;

    function getAssetAddress() external view returns (address);
    
    function getDenomination() external view returns (bytes32);
    
    function setManualPrice(int256) external;
    
    function setManualOverride(bool) external;

}
