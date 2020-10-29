pragma solidity ^0.7.0;

import "./LP/LP.sol";

contract LPFactory {
    mapping(uint256 => address) public LiquidityPools;
    uint256 public LiquidityPoolsCreated;

    function createLiquidityPool(
        address _liquidAsset,
        address _stakedAsset,
        address _stakedAssetLockerFactory,
        string memory name,
        string memory symbol
    ) public {
        LP lpool = new LP(
            _liquidAsset,
            _stakedAsset,
            _stakedAssetLockerFactory,
            name,
            symbol
            //IERC20(_liquidAsset)
        );
        LiquidityPools[LiquidityPoolsCreated] = address(lpool);
        LiquidityPoolsCreated++;
    }

    function getLiquidityPool(uint256 _ind) public view returns (address) {
        return LiquidityPools[_ind];
    }
}
