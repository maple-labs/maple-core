// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

interface IOracle {
    function getLatestPrice()  external view returns(int256);
    
    function getAssetAddress() external view returns(address);
    
    function getDenomination() external view returns(bytes32);
    
    function setManualPrice(int256)    external;
    
    function setManualOverride(bool)   external;
    
    function changeAggregator(address) external;
    
}
