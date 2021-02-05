// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

interface IGlobals {
    function governor() external view returns (address);

    function mpl() external view returns (address);

    function mapleTreasury() external view returns (address);

    function treasuryFee() external view returns (uint256);

    function investorFee() external view returns (uint256);

    function gracePeriod() external view returns (uint256);

    function drawdownGracePeriod() external view returns (uint256);

    function swapOutRequired() external view returns (uint256);

    function isValidLoanAsset(address) external view returns (bool);

    function isValidCollateralAsset(address) external view returns (bool);

    function BFactory() external view returns (address);

    function setBFactory() external view returns (uint256);

    function isValidPoolDelegate(address) external view returns (bool);

    function validLoanAssets() external view returns (address[] memory);

    function validCollateralAssets() external view returns (address[] memory);

    function unstakeDelay() external view returns (uint256);

    function loanFactory() external view returns (address);

    function poolFactory() external view returns (address);

    function getPrice(address) external view returns (uint256);

    function isValidCalc(address) external view returns (bool);

    function isValidLoanFactory(address) external view returns (bool);

    function isValidSubFactory(address, address, uint8) external view returns (bool);

    function isValidPoolFactory(address) external view returns (bool);
    
    function getLatestPrice(address) external view returns (uint256);
    
    function defaultUniswapPath(address, address) external view returns (address);
}
