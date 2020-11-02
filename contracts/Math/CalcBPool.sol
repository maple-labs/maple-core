pragma solidity 0.7.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interface/IBPool.sol";

//we might want to do this with functions built into BPool 
//these functions will give us the ammount out if they cashed out
//this would not be the same as how much money they put in as it includes slippage and fees

library CalcBPool {

  uint constant _ONE = 10**18;

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

  function BPTVal(address _BPoolAddy,address _staker, address _liquidAssetContract) internal view returns (uint256) {
    //calculates the value of BPT in unites of _liquidAssetContract, in 'wei' (decimals) for this token
    IBPool _IBPool = IBPool(_BPoolAddy);
    IERC20 _IBPoolERC20 = IERC20(_BPoolAddy);
    uint _BPTBal = _IBPoolERC20.balanceOf(_staker);
    uint _BPTtotal = _IBPoolERC20.totalSupply();
    uint _liquidAssetBal = _IBPool.getBalance(_liquidAssetContract);
    uint _liquidAssetWeight = _IBPool.getNormalizedWeight(_liquidAssetContract);
    uint _val = SafeMath.div(bdiv(_BPTBal,_BPTtotal)*bdiv(_liquidAssetBal,_liquidAssetWeight),_ONE);
    //we have to divide out the extra _ONE with normal safemath
    //the two divisions must be separate, as coins that are lower decimals(like usdc) will underflow and give 0
    //due to the fact that the _liquidAssetWeight is a synthetic float from bpool, IE  x*10^18 where 0<x<1
    //the result here is 
    return _val;
  }
  
}