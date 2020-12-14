// SPDX-License-Identifier: MIT
pragma solidity 0.7.0;

interface IBPool {
    function isFinalized() external view returns (bool);

    function isBound(address) external view returns (bool);

    function getNumTokens() external view returns (uint);

    function getBalance(address) external view returns (uint);

    function getNormalizedWeight(address) external view returns (uint);

    function getDenormalizedWeight(address) external view returns (uint);

    function getTotalDenormalizedWeight() external view returns (uint);

    function getSwapFee() external view returns (uint);

    function totalSupply() external view returns (uint);

    function calcSingleOutGivenPoolIn(
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint poolSupply,
        uint totalWeight,
        uint poolAmountIn,
        uint swapFee
    ) external pure returns (uint);

    function calcPoolInGivenSingleOut(
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint poolSupply,
        uint totalWeight,
        uint tokenAmountOut,
        uint swapFee
    ) external pure returns (uint);

}