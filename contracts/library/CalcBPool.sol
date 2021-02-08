// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IBPool.sol";
import "../interfaces/IGlobals.sol";

library CalcBPool {

    using SafeMath for uint256;

    uint256 constant WAD = 10 ** 18;

    /// @dev Official balancer pool bdiv() function, does synthetic float with 10^-18 precision.
    function bdiv(uint256 a, uint256 b) public pure returns (uint256) {
        require(b != 0, "ERR_DIV_ZERO");
        uint256 c0 = a * WAD;
        require(a == 0 || c0 / a == WAD, "ERR_DIV_INTERNAL"); // bmul overflow
        uint256 c1 = c0 + (b / 2);
        require(c1 >= c0, "ERR_DIV_INTERNAL"); //  badd require
        uint256 c2 = c1 / b;
        return c2;
    }

    /// @dev Calculates the value of BPT in units of _liquidityAssetContract in 'wei' (decimals) for this token.
    // TODO: Identify use and add NatSpec later.
    function BPTVal(
        address _pool,
        address _pair,
        address _staker,
        address _stakeLocker
    ) public view returns (uint256) {

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
        uint256 _val = bdiv(amountStakedBPT, totalSupplyBPT).mul(bdiv(liquidityAssetBalance, liquidityAssetWeight)).div(WAD);
        
        //we have to divide out the extra WAD with normal safemath
        //the two divisions must be separate, as coins that are lower decimals(like usdc) will underflow and give 0
        //due to the fact that the _liquidityAssetWeight is a synthetic float from bpool, IE  x*10^18 where 0<x<1
        //the result here is
        return _val;
    }

    /** 
        @dev Calculate _pair swap out value of staker BPT balance escrowed in stakeLocker.
        @param pool        Balancer pool that issues the BPTs.
        @param pair        Swap out asset (e.g. USDC) to receive when burning BPTs.
        @param staker      Address that deposited BPTs to stakeLocker.
        @param stakeLocker Escrows BPTs deposited by staker.
        @return USDC swap out value of staker BPTs.
    */
    function getSwapOutValue(
        address pool,
        address pair,
        address staker,
        address stakeLocker
    ) public view returns (uint256) {

        // Fetch balancer pool token information.
        IBPool bPool            = IBPool(pool);
        uint256 tokenBalanceOut = bPool.getBalance(pair);
        uint256 tokenWeightOut  = bPool.getDenormalizedWeight(pair);
        uint256 poolSupply      = bPool.totalSupply();
        uint256 totalWeight     = bPool.getTotalDenormalizedWeight();
        uint256 swapFee         = bPool.getSwapFee();

        // Fetch amount staked in stakeLocker by staker.
        uint256 poolAmountIn = IERC20(stakeLocker).balanceOf(staker);

        // Returns amount of BPTs required to extract tokenAmountOut.
        uint256 tokenAmountOut = bPool.calcSingleOutGivenPoolIn(
            tokenBalanceOut,
            tokenWeightOut,
            poolSupply,
            totalWeight,
            poolAmountIn,
            swapFee
        );

        return tokenAmountOut;
    }

    /** 
        @dev Calculate _pair swap out value of staker BPT balance escrowed in stakeLocker.
        @param pool        Balancer pool that issues the BPTs.
        @param pair        Swap out asset (e.g. USDC) to receive when burning BPTs.
        @param stakeLocker Escrows BPTs deposited by staker.
        @return USDC swap out value of staker BPTs.
    */
    function getSwapOutValueLocker(
        address pool,
        address pair,
        address stakeLocker
    ) public returns (uint256) {

        // Fetch balancer pool token information.
        IBPool bPool            = IBPool(pool);
        uint256 tokenBalanceOut = bPool.getBalance(pair);
        uint256 tokenWeightOut  = bPool.getDenormalizedWeight(pair);
        uint256 poolSupply      = bPool.totalSupply();
        uint256 totalWeight     = bPool.getTotalDenormalizedWeight();
        uint256 swapFee         = bPool.getSwapFee();

        // Fetch BPT balance of stakeLocker by staker.
        uint256 poolAmountIn = bPool.balanceOf(stakeLocker);

        // Returns amount of BPTs required to extract tokenAmountOut.
        uint256 tokenAmountOut = bPool.calcSingleOutGivenPoolIn(
            tokenBalanceOut,
            tokenWeightOut,
            poolSupply,
            totalWeight,
            poolAmountIn,
            swapFee
        );

        return tokenAmountOut;
    }

    /**
        @dev Calculates BPTs required if burning BPTs for pair, given supplied tokenAmountOutRequired.
        @param  bpool              Balancer pool that issues the BPTs.
        @param  pair               Swap out asset (e.g. USDC) to receive when burning BPTs.
        @param  staker             Address that deposited BPTs to stakeLocker.
        @param  stakeLocker        Escrows BPTs deposited by staker.
        @param  pairAmountRequired Amount of pair tokens out required.
        @return [0] = poolAmountIn required
                [1] = poolAmountIn currently staked.
    */
    function getPoolSharesRequired(
        address bpool,
        address pair,
        address staker,
        address stakeLocker,
        uint256 pairAmountRequired
    ) public view returns (uint256, uint256) {

        IBPool bPool = IBPool(bpool);

        uint256 tokenBalanceOut = bPool.getBalance(pair);
        uint256 tokenWeightOut  = bPool.getDenormalizedWeight(pair);
        uint256 poolSupply      = bPool.totalSupply();
        uint256 totalWeight     = bPool.getTotalDenormalizedWeight();
        uint256 swapFee         = bPool.getSwapFee();

        // Fetch amount of BPTs required to burn to receive pairAmountRequired.
        uint256 poolAmountInRequired = bPool.calcPoolInGivenSingleOut(
            tokenBalanceOut,
            tokenWeightOut,
            poolSupply,
            totalWeight,
            pairAmountRequired,
            swapFee
        );

        // Fetch amount staked in _stakeLocker by staker.
        uint256 stakerBalance = IERC20(stakeLocker).balanceOf(staker);

        return (poolAmountInRequired, stakerBalance);
    }
    
}
