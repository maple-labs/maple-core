// SPDX-License-Identifier: MIT
pragma solidity 0.7.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interface/IBPool.sol";

//we might want to do this with functions built into BPool
//these functions will give us the ammount out if they cashed out
//this would not be the same as how much money they put in as it includes slippage and fees

library CalcBPool {

    using SafeMath for uint256;
    uint256 constant _ONE = 10**18;

    /// @notice Official balancer pool bdiv() function, does synthetic float with 10^-18 precision.
    function bdiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "ERR_DIV_ZERO");
        uint256 c0 = a * _ONE;
        require(a == 0 || c0 / a == _ONE, "ERR_DIV_INTERNAL"); // bmul overflow
        uint256 c1 = c0 + (b / 2);
        require(c1 >= c0, "ERR_DIV_INTERNAL"); //  badd require
        uint256 c2 = c1 / b;
        return c2;
    }

    /// @notice Calculates the value of BPT in units of _liquidityAssetContract, in 'wei' (decimals) for this token
    function BPTVal(
        address _balancerPool,
        address _staker,
        address _liquidityAsset,
        address _stakeLocker
    ) internal view returns (uint256) {

        //calculates the value of BPT in unites of _liquidityAssetContract, in 'wei' (decimals) for this token

        // Create interfaces for the balancerPool as a Pool and as an ERC-20 token.
        IBPool bPool = IBPool(_balancerPool);
        IERC20 bPoolERC20 = IERC20(_balancerPool);

        // FDTs are minted 1:1 (in wei) in the StakeLocker when staking BPTs, thus representing stake amount.
        // These are burned when withdrawing staked BPTs, thus representing the current stake amount.
        uint256 amountStakedBPT = IERC20(_stakeLocker).balanceOf(_staker);
        uint256 totalSupplyBPT = bPoolERC20.totalSupply();
        uint256 liquidityAssetBalance = bPool.getBalance(_liquidityAsset);
        uint256 liquidityAssetWeight = bPool.getNormalizedWeight(_liquidityAsset);
        uint256 _val = bdiv(amountStakedBPT, totalSupplyBPT).mul(bdiv(liquidityAssetBalance, liquidityAssetWeight)).div(_ONE);
        
        //we have to divide out the extra _ONE with normal safemath
        //the two divisions must be separate, as coins that are lower decimals(like usdc) will underflow and give 0
        //due to the fact that the _liquidityAssetWeight is a synthetic float from bpool, IE  x*10^18 where 0<x<1
        //the result here is
        return _val;
    }
}
