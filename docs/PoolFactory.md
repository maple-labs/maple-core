

## Functions:
[`constructor(address _globals, address _slFactory, address _llFactory)`](#PoolFactory-constructor-address-address-address-)
[`createPool(address liquidityAsset, address stakeAsset, uint256 stakingFee, uint256 delegateFee)`](#PoolFactory-createPool-address-address-uint256-uint256-)

## Events:
[`PoolCreated(string tUUID, address pool, address delegate, address liquidityAsset, address stakeAsset, address liquidityLocker, address stakeLocker, uint256 stakingFee, uint256 delegateFee, string name, string symbol)`](#PoolFactory-PoolCreated-string-address-address-address-address-address-address-uint256-uint256-string-string-)

## <u>Functions</u>

### `constructor(address _globals, address _slFactory, address _llFactory)`
No description

### `createPool(address liquidityAsset, address stakeAsset, uint256 stakingFee, uint256 delegateFee)`
Instantiates a Pool contract.
        @param  liquidityAsset The asset escrowed in LiquidityLocker.
        @param  stakeAsset     The asset escrowed in StakeLocker.
        @param  stakingFee     Fee that stakers earn on interest, in bips.
        @param  delegateFee    Fee that pool delegate earns on interest, in bips.

## <u>Events</u>

### `PoolCreated(string tUUID, address pool, address delegate, address liquidityAsset, address stakeAsset, address liquidityLocker, address stakeLocker, uint256 stakingFee, uint256 delegateFee, string name, string symbol)`
No description