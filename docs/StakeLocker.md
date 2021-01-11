

## Functions:
[`constructor(address _stakeAsset, address _liquidityAsset, address _owner, address _globals)`](#StakeLocker-constructor-address-address-address-address-)
[`stake(uint256 amt)`](#StakeLocker-stake-uint256-)
[`unstake(uint256 amt)`](#StakeLocker-unstake-uint256-)
[`deleteLP()`](#StakeLocker-deleteLP--)
[`finalizeLP()`](#StakeLocker-finalizeLP--)
[`withdrawETH(address payable dst)`](#StakeLocker-withdrawETH-address-payable-)
[`getUnstakeableBalance(address staker)`](#StakeLocker-getUnstakeableBalance-address-)

## Events:
[`BalanceUpdated(address who, address token, uint256 balance)`](#StakeLocker-BalanceUpdated-address-address-uint256-)
[`Stake(uint256 _amount, address _staker)`](#StakeLocker-Stake-uint256-address-)
[`Unstake(uint256 _amount, address _staker)`](#StakeLocker-Unstake-uint256-address-)

## <u>Functions</u>

### `constructor(address _stakeAsset, address _liquidityAsset, address _owner, address _globals)`
No description

### `stake(uint256 amt)`
Deposit amt of stakeAsset, mint FDTs to msg.sender.
        @param amt Amount of stakeAsset (BPTs) to deposit.

### `unstake(uint256 amt)`
Withdraw amt of stakeAsset, burn FDTs for msg.sender.
        @param amt Amount of stakeAsset (BPTs) to withdraw.

### `deleteLP()`
Delete the pool.

### `finalizeLP()`
Finalize the pool.

### `withdrawETH(address payable dst)`
Withdraw ETH directly from this locker.
        @param dst Address to send ETH to.

### `getUnstakeableBalance(address staker)`
Returns information for staker's unstakeable balance.
        @param staker The address to view information for.
        @return Amount of BPTs staker can unstake.

## <u>Events</u>

### `BalanceUpdated(address who, address token, uint256 balance)`
No description

### `Stake(uint256 _amount, address _staker)`
No description

### `Unstake(uint256 _amount, address _staker)`
No description
