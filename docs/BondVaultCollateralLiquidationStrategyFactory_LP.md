

## Functions:
[`newLocker(address _bondVault, address _poolDelegate, address _collateralAsset, address _investmentAsset)`](#BondVaultCollateralLiquidationStrategyFactory_LP-newLocker-address-address-address-address-)

## Events:
[`NewLocker(address _locker, address _bondVault, address _poolDelegate, address _collateralAsset, address _investmentAsset)`](#BondVaultCollateralLiquidationStrategyFactory_LP-NewLocker-address-address-address-address-address-)

## <u>Functions</u>

## `newLocker(address _bondVault, address _poolDelegate, address _collateralAsset, address _investmentAsset)`
Instantiates a new locker.


### Parameters:
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; `_poolDelegate`: PoolDelegate instantiating the locker.

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; `_bondVault`: BondVault from which collateral is liquidated.

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; `_collateralAsset`: Address of the (ERC-20) CollateralAsset.

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; `_investmentAsset`: Address of the (ERC-20) InvestmentAsset the CollateralAsset is exchanged for.

## <u>Events</u>

## `NewLocker(address _locker, address _bondVault, address _poolDelegate, address _collateralAsset, address _investmentAsset)`
Returns the address of a newLocker when created.


### Parameters:
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; `_locker`: Address of the instantiated locker.

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; `_poolDelegate`: (Indexed) PoolDelegate instantiating the locker.

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; `_bondVault`: (Indexed) BondVault from which collateral is liquidated.

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; `_collateralAsset`: Address of the (ERC-20) CollateralAsset.

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; `_investmentAsset`: Address of the (ERC-20) InvestmentAsset the CollateralAsset is exchanged for.
