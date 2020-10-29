pragma solidity ^0.7.0;

import "./LP/LP.sol";

contract LPFactory {
    mapping(uint256 => address) public LiquidityPools;
    uint256 public LiquidityPoolsCreated;

    function createLiquidityPool(
        address _investmentAsset,
        address _stakedAsset,
        address _stakedAssetLockerFactory,
        string memory name,
        string memory symbol
    ) public {
        LP lpool = new LP(
            _investmentAsset,
            _stakedAsset,
            _stakedAssetLockerFactory,
            name,
            symbol,
            IERC20(_investmentAsset)
        );
        LiquidityPools[LiquidityPoolsCreated] = address(lpool);
        LiquidityPoolsCreated++;
    }
}
