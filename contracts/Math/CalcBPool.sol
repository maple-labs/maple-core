pragma solidity 0.7.0;
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../interface/IBPool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
//we might want to do this with functions built into BPool 
//these functions will give us the ammount out if they cashed out
//this would not be the same as how much money they put in as it includes slippage and fees
library CalcBPool {
      function bdiv(uint256 a, uint256 b,uint256 _tokenOne) internal pure returns (uint256) {
        require(b != 0, "ERR_DIV_ZERO");
        uint256 c0 = a * _tokenOne;
        require(a == 0 || c0 / a == _tokenOne, "ERR_DIV_INTERNAL"); // bmul overflow
        uint256 c1 = c0 + (b / 2);
        require(c1 >= c0, "ERR_DIV_INTERNAL"); //  badd require
        uint256 c2 = c1 / b;
        return c2;
    }
  function BPTVal(address _BPoolAddy,address _staker, address _liquidAssetContract) internal view returns (uint256) {

    //calculates the value of BPT in unites of _liquidAssetContract, in 'wei' (decimals) for this token
    //maybe should be 10**6 for USDC... think about that
    uint _ONE = 10**18;
    IBPool _IBPool = IBPool(_BPoolAddy);
    IERC20 _IBPoolERC20 = IERC20(_BPoolAddy);
    uint _BPTBal = _IBPoolERC20.balanceOf(_staker);
    uint _BPTtotal = _IBPoolERC20.totalSupply();
    uint _liquidAssetBal = _IBPool.getBalance(_liquidAssetContract);
    uint _liquidAssetWeight = _IBPool.getNormalizedWeight(_liquidAssetContract);
    uint _val = SafeMath.div(bdiv(_BPTBal,_BPTtotal,_ONE)*bdiv(_liquidAssetBal,_liquidAssetWeight,_ONE),_ONE);
    //this is underflowing becauyse of the division of liquidassetbal over BPTTotal
    //these mults will not overflow. but i used safemath anyways
    return _val;
  }
}