// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

interface IGlobals {
    function governor() external view returns (address);

    function admin() external view returns (address);

    function mpl() external view returns (address);

    function mapleTreasury() external view returns (address);

    function isExemptFromTransferRestriction(address) external view returns (bool);

    function isValidBalancerPool(address) external view returns (bool);

    function treasuryFee() external view returns (uint256);

    function investorFee() external view returns (uint256);

    function gracePeriod() external view returns (uint256);

    function drawdownGracePeriod() external view returns (uint256);

    function swapOutRequired() external view returns (uint256);

    function isValidLiquidityAsset(address) external view returns (bool);

    function isValidCollateralAsset(address) external view returns (bool);

    function isValidPoolDelegate(address) external view returns (bool);

    function validLiquidityAssets() external view returns (address[] memory);

    function validCollateralAssets() external view returns (address[] memory);

    function loanFactory() external view returns (address);

    function poolFactory() external view returns (address);

    function getPrice(address) external view returns (uint256);

    function isValidCalc(address, uint8) external view returns (bool);

    function isValidLoanFactory(address) external view returns (bool);

    function isValidSubFactory(address, address, uint8) external view returns (bool);

    function isValidPoolFactory(address) external view returns (bool);
    
    function getLatestPrice(address) external view returns (uint256);
    
    function defaultUniswapPath(address, address) external view returns (address);

    function minLoanEquity() external view returns (uint256);
    
    function maxSwapSlippage() external view returns (uint256);

    function protocolPaused() external view returns (bool);

    function stakerCooldownPeriod() external view returns(uint256);

    function lpCooldownPeriod() external view returns(uint256);

    function stakerUnstakeWindow() external view returns(uint256);

    function lpWithdrawWindow() external view returns(uint256);
}
