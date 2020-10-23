

## Functions:
[`constructor(address _bondVault, address _poolDelegate, address _collateralAsset, address _investmentAsset)`](#BondVaultCollateralLiquidationStrategy_LP-constructor-address-address-address-address-)
[`initiateLiquidation(address _bondVault)`](#BondVaultCollateralLiquidationStrategy_LP-initiateLiquidation-address-)
[`finaliseLiquidation(address _bondVault, uint256 _investmentAssetWaived)`](#BondVaultCollateralLiquidationStrategy_LP-finaliseLiquidation-address-uint256-)
[`withdrawFromLocker(uint256 _assetAmount)`](#BondVaultCollateralLiquidationStrategy_LP-withdrawFromLocker-uint256-)


## <u>Functions</u>

## `constructor(address _bondVault, address _poolDelegate, address _collateralAsset, address _investmentAsset)`
Constructor for BondVaultCollateralLiquidationStrategy_LP.sol


### Parameters:
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; `_bondVault`: BondVault from which collateral is liquidated.

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; `_poolDelegate`: PoolDelegate of the liquidity pool.

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; `_collateralAsset`: Address of the (ERC-20) CollateralAsset.

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; `_investmentAsset`: Address of the (ERC-20) InvestmentAsset the (ERC-20) CollateralAsset is exchanged for.

## `initiateLiquidation(address _bondVault)`
Initiate liquidation of BondVault collateral.


### Parameters:
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; `_bondVault`: BondVault from which collateral is liquidated.


### Returns:
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; Represents whether or not liquidation initiation was successful.

## `finaliseLiquidation(address _bondVault, uint256 _investmentAssetWaived)`
Finalise liquidation of BondVault collateral.


### Parameters:
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; `_bondVault`: BondVault from which collateral is liquidated.

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; `_investmentAssetWaived`: Amount (10 ** decimals) of InvestmentAsset stakers will not cover.


### Returns:
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; Amount (10 ** decimals) of InvestmentAsset returned to liquidity pool InvestmentAsset locker.

## `withdrawFromLocker(uint256 _assetAmount)`
PoolDelegate override/manual withdrawal from this locker.


### Parameters:
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; `_assetAmount`: Amount (10 ** decimals) of InvestmentAsset to withdraw from this locker.


### Returns:
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; Amount (10 ** decimals) of InvestmentAsset returned to the PoolDelegate.

## <u>Events</u>
