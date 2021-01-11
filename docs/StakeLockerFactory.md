

## Functions:
[`newLocker(address stakeAsset, address liquidityAsset, address globals)`](#StakeLockerFactory-newLocker-address-address-address-)

## Events:
[`StakeLockerCreated(address owner, address stakeLocker, address stakeAsset, address liquidityAsset, string name, string symbol)`](#StakeLockerFactory-StakeLockerCreated-address-address-address-address-string-string-)

## <u>Functions</u>

### `newLocker(address stakeAsset, address liquidityAsset, address globals)`
Instantiate a StakeLocker contract.
        @return Address of the instantiated stake locker.
        @param stakeAsset     Address of the stakeAsset (generally a balancer pool).
        @param liquidityAsset Address of the liquidityAsset (as defined in the pool).
        @param globals        Address of the MapleGlobals contract.

## <u>Events</u>

### `StakeLockerCreated(address owner, address stakeLocker, address stakeAsset, address liquidityAsset, string name, string symbol)`
No description