// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IBPool.sol";
import "../interfaces/IGlobals.sol";
// import "hardhat/console.sol";

//we might want to do this with functions built into BPool
//these functions will give us the ammount out if they cashed out
//this would not be the same as how much money they put in as it includes slippage and fees

contract CalcBPool {

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
        address _pool,
        address _pair,
        address _staker,
        address _stakeLocker
    ) external view returns (uint256) {

        //calculates the value of BPT in unites of _liquidityAssetContract, in 'wei' (decimals) for this token

        // Create interfaces for the balancerPool as a Pool and as an ERC-20 token.
        IBPool bPool = IBPool(_pool);
        IERC20 bPoolERC20 = IERC20(_pool);

        // FDTs are minted 1:1 (in wei) in the StakeLocker when staking BPTs, thus representing stake amount.
        // These are burned when withdrawing staked BPTs, thus representing the current stake amount.
        uint256 amountStakedBPT = IERC20(_stakeLocker).balanceOf(_staker);
        uint256 totalSupplyBPT = bPoolERC20.totalSupply();
        uint256 liquidityAssetBalance = bPool.getBalance(_pair);
        uint256 liquidityAssetWeight = bPool.getNormalizedWeight(_pair);
        uint256 _val = bdiv(amountStakedBPT, totalSupplyBPT).mul(bdiv(liquidityAssetBalance, liquidityAssetWeight)).div(_ONE);
        
        //we have to divide out the extra _ONE with normal safemath
        //the two divisions must be separate, as coins that are lower decimals(like usdc) will underflow and give 0
        //due to the fact that the _liquidityAssetWeight is a synthetic float from bpool, IE  x*10^18 where 0<x<1
        //the result here is
        return _val;
    }

    /// @notice Calculates the USDC swap out value of the _staker BPTs held in _stakeLocker.
    /// @param _pool is the official Maple Balancer pool.
    /// @param _pair is the asset paired 50/50 with MPL in the official Maple Balancer pool.
    /// @param _staker is the staker who deposited to the StakeLocker.
    /// @param _stakeLocker is the address of the StakeLocker.
    /// @return uint, USDC swap out value of _staker BPTs.
    function getSwapOutValue(
        address _pool,
        address _pair,
        address _staker,
        address _stakeLocker
    ) external view returns (uint256) {

        // Fetch balancer pool token information.
        IBPool bPool = IBPool(_pool);
        uint256 tokenBalanceOut = bPool.getBalance(_pair);
        uint256 tokenWeightOut = bPool.getDenormalizedWeight(_pair);
        uint256 poolSupply = bPool.totalSupply();
        uint256 totalWeight = bPool.getTotalDenormalizedWeight();
        uint256 swapFee = bPool.getSwapFee();

        // Fetch amount staked in _stakeLocker by _staker.
        uint256 poolAmountIn = IERC20(_stakeLocker).balanceOf(_staker);
        
        // console.log("poolAmountIn", poolAmountIn);

        // Returns amount of BPTs required to extract tokenAmountOut.
        uint256 tokenAmountOut = bPool.calcSingleOutGivenPoolIn(
            tokenBalanceOut,
            tokenWeightOut,
            poolSupply,
            totalWeight,
            poolAmountIn,
            swapFee
        );

        // console.log("tokenAmountOut", tokenAmountOut);

        return tokenAmountOut;
    }

    /// @notice Calculates the pool shares required for supplied tokenAmountOut (USDC).
    /// @param _pool is the official Maple Balancer pool.
    /// @param _pair is the asset paired 50/50 with MPL in the official Maple Balancer pool.
    /// @param _staker is the staker who deposited to the StakeLocker.
    /// @param _stakeLocker is the address of the StakeLocker.
    /// @param _tokenAmountOutRequired is the amount of USDC out required.
    /// @return uint, [0] = poolAmountIn required
    /// @return uint, [1] = poolAmountIn currently staked.
    function getPoolSharesRequired(
        address _pool,
        address _pair,
        address _staker,
        address _stakeLocker,
        uint256 _tokenAmountOutRequired
    ) external view returns (uint256, uint256) {

        // Fetch balancer pool token information.
        IBPool bPool = IBPool(_pool);
        uint256 tokenBalanceOut = bPool.getBalance(_pair);
        uint256 tokenWeightOut = bPool.getDenormalizedWeight(_pair);
        uint256 poolSupply = bPool.totalSupply();
        uint256 totalWeight = bPool.getTotalDenormalizedWeight();
        uint256 swapFee = bPool.getSwapFee();

        // Returns amount of BPTs required to extract tokenAmountOut.
        uint256 poolAmountInRequired = bPool.calcSingleOutGivenPoolIn(
            tokenBalanceOut,
            tokenWeightOut,
            poolSupply,
            totalWeight,
            _tokenAmountOutRequired,
            swapFee
        );

        // Fetch amount staked in _stakeLocker by _staker.
        uint256 stakerBalance = IERC20(_stakeLocker).balanceOf(_staker);

        // console.log("poolAmountInRequired", poolAmountInRequired);
        // console.log("stakerBalance", stakerBalance);

        return (poolAmountInRequired, stakerBalance.div(_ONE));
    }
}
