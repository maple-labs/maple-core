

## Functions:
[`constructor(address _globals)`](#PoolFactory-constructor-address-)
[`setGlobals(address newGlobals)`](#PoolFactory-setGlobals-address-)
[`createPool(address liquidityAsset, address stakeAsset, address slFactory, address llFactory, uint256 stakingFee, uint256 delegateFee, uint256 liquidityCap)`](#PoolFactory-createPool-address-address-address-address-uint256-uint256-uint256-)

## Events:
[`PoolCreated(string tUUID, address pool, address delegate, address liquidityAsset, address stakeAsset, address liquidityLocker, address stakeLocker, uint256 stakingFee, uint256 delegateFee, uint256 liquidityCap, string name, string symbol)`](#PoolFactory-PoolCreated-string-address-address-address-address-address-address-uint256-uint256-uint256-string-string-)

## <u>Functions</u>

### `constructor(address _globals)`
No description

### `setGlobals(address newGlobals)`
Update the maple globals contract
        @param  newGlobals Address of new maple globals contract

### `createPool(address liquidityAsset, address stakeAsset, address slFactory, address llFactory, uint256 stakingFee, uint256 delegateFee, uint256 liquidityCap)`
Instantiates a Pool contract.
        @param  liquidityAsset The asset escrowed in LiquidityLocker.
        @param  stakeAsset     The asset escrowed in StakeLocker.
        @param  slFactory      The factory to instantiate a Stake Locker from.
        @param  llFactory      The factory to instantiate a Liquidity Locker from.
        @param  stakingFee     Fee that stakers earn on interest, in bips.
        @param  delegateFee    Fee that pool delegate earns on interest, in bips.
        @param  liquidityCap   Amount of liquidity tokens accepted by the pool.

## <u>Events</u>

### `PoolCreated(string tUUID, address pool, address delegate, address liquidityAsset, address stakeAsset, address liquidityLocker, address stakeLocker, uint256 stakingFee, uint256 delegateFee, uint256 liquidityCap, string name, string symbol)`
No description
