// SPDX-License-Identifier: MIT
pragma solidity 0.7.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interface/IBPool.sol";

//we might want to do this with functions built into BPool
//these functions will give us the ammount out if they cashed out
//this would not be the same as how much money they put in as it includes slippage and fees

library CalcBPool {
    uint256 constant _ONE = 10**18;

    //we need to use this division function which does synthetic float with 10^-18 precision.
    //it is from balancer pool

    function bdiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "ERR_DIV_ZERO");
        uint256 c0 = a * _ONE;
        require(a == 0 || c0 / a == _ONE, "ERR_DIV_INTERNAL"); // bmul overflow
        uint256 c1 = c0 + (b / 2);
        require(c1 >= c0, "ERR_DIV_INTERNAL"); //  badd require
        uint256 c2 = c1 / b;
        return c2;
    }

    function BPTVal(
        address _BPoolAddy,
        address _staker,
        address _liquidityAssetContract,
        address _stakeAssetLocker
    ) internal view returns (uint256) {
        //calculates the value of BPT in unites of _liquidityAssetContract, in 'wei' (decimals) for this token
        IBPool _IBPool = IBPool(_BPoolAddy);
        IERC20 _IBPoolERC20 = IERC20(_BPoolAddy);
        uint256 _FDTBalBPT = IERC20(_stakeAssetLocker).balanceOf(_staker); //bal of FDTs that are 1:1 with BPTs
        //the number of BPT staked per _staker is the same as his balance of staked asset locker tokens.
        //this is used to prove it exists and is staked currently.
        uint256 _BPTtotal = _IBPoolERC20.totalSupply();
        uint256 _liquidityAssetBal = _IBPool.getBalance(_liquidityAssetContract);
        uint256 _liquidityAssetWeight = _IBPool.getNormalizedWeight(_liquidityAssetContract);
        uint256 _val =
            SafeMath.div(
                bdiv(_FDTBalBPT, _BPTtotal) * bdiv(_liquidityAssetBal, _liquidityAssetWeight),
                _ONE
            );
        //we have to divide out the extra _ONE with normal safemath
        //the two divisions must be separate, as coins that are lower decimals(like usdc) will underflow and give 0
        //due to the fact that the _liquidityAssetWeight is a synthetic float from bpool, IE  x*10^18 where 0<x<1
        //the result here is
        return _val;
    }
}
