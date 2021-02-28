

## Functions:
[`constructor(address _poolDelegate, address _liquidityAsset, address _stakeAsset, address _slFactory, address _llFactory, uint256 _stakingFee, uint256 _delegateFee, uint256 _liquidityCap, string name, string symbol)`](#Pool-constructor-address-address-address-address-address-uint256-uint256-uint256-string-string-)
[`finalize()`](#Pool-finalize--)
[`getInitialStakeRequirements()`](#Pool-getInitialStakeRequirements--)
[`getPoolSharesRequired(address bpool, address pair, address staker, address stakeLocker, uint256 pairAmountRequired)`](#Pool-getPoolSharesRequired-address-address-address-address-uint256-)
[`isDepositAllowed(uint256 depositAmt)`](#Pool-isDepositAllowed-uint256-)
[`setLiquidityCap(uint256 newLiquidityCap)`](#Pool-setLiquidityCap-uint256-)
[`deposit(uint256 amt)`](#Pool-deposit-uint256-)
[`withdraw(uint256 amt)`](#Pool-withdraw-uint256-)
[`fundLoan(address loan, address dlFactory, uint256 amt)`](#Pool-fundLoan-address-address-uint256-)
[`claim(address loan, address dlFactory)`](#Pool-claim-address-address-)
[`deactivate(uint256 confirmation)`](#Pool-deactivate-uint256-)
[`calcWithdrawPenalty(uint256 amt, address who)`](#Pool-calcWithdrawPenalty-uint256-address-)
[`setPenaltyDelay(uint256 _penaltyDelay)`](#Pool-setPenaltyDelay-uint256-)
[`setPrincipalPenalty(uint256 _newPrincipalPenalty)`](#Pool-setPrincipalPenalty-uint256-)
[`setLockupPeriod(uint256 _newLockupPeriod)`](#Pool-setLockupPeriod-uint256-)
[`setAllowlistStakeLocker(address user, bool status)`](#Pool-setAllowlistStakeLocker-address-bool-)
[`claimableFunds(address lp)`](#Pool-claimableFunds-address-)
[`withdrawFunds()`](#Pool-withdrawFunds--)

## Events:
[`LoanFunded(address loan, address debtLocker, uint256 amountFunded)`](#Pool-LoanFunded-address-address-uint256-)
[`BalanceUpdated(address who, address token, uint256 balance)`](#Pool-BalanceUpdated-address-address-uint256-)
[`Claim(address loan, uint256 interest, uint256 principal, uint256 fee)`](#Pool-Claim-address-uint256-uint256-uint256-)
[`DefaultSuffered(address loan, uint256 defaultSuffered, uint256 bptsBurned, uint256 bptsReturned, uint256 liquidityAssetRecoveredFromBurn)`](#Pool-DefaultSuffered-address-uint256-uint256-uint256-uint256-)

## <u>Functions</u>

### `constructor(address _poolDelegate, address _liquidityAsset, address _stakeAsset, address _slFactory, address _llFactory, uint256 _stakingFee, uint256 _delegateFee, uint256 _liquidityCap, string name, string symbol)`
Constructor for a Pool.
        @param  _poolDelegate   The address that has manager privlidges for the Pool.
        @param  _liquidityAsset The asset escrowed in LiquidityLocker.
        @param  _stakeAsset     The asset escrowed in StakeLocker.
        @param  _slFactory      Factory used to instantiate StakeLocker.
        @param  _llFactory      Factory used to instantiate LiquidityLocker.
        @param  _stakingFee     Fee that stakers earn on interest, in bips.
        @param  _delegateFee    Fee that _poolDelegate earns on interest, in bips.
        @param  _liquidityCap   Amount of liquidity tokens accepted by the pool.
        @param  name            Name of pool token.
        @param  symbol          Symbol of pool token.

### `finalize()`
Finalize the pool, enabling deposits. Checks poolDelegate amount deposited to StakeLocker.

### `getInitialStakeRequirements()`
Returns information on the stake requirements.
        @return [0] = Min amount of liquidityAsset coverage from staking required
                [1] = Present amount of liquidityAsset coverage from staking
                [2] = If enough stake is present from Pool Delegate for finalization
                [3] = Staked BPTs required for minimum liquidityAsset coverage
                [4] = Current staked BPTs

### `getPoolSharesRequired(address bpool, address pair, address staker, address stakeLocker, uint256 pairAmountRequired)`
Calculates BPTs required if burning BPTs for pair, given supplied tokenAmountOutRequired.
        @param  bpool              Balancer pool that issues the BPTs.
        @param  pair               Swap out asset (e.g. USDC) to receive when burning BPTs.
        @param  staker             Address that deposited BPTs to stakeLocker.
        @param  stakeLocker        Escrows BPTs deposited by staker.
        @param  pairAmountRequired Amount of pair tokens out required.
        @return [0] = poolAmountIn required
                [1] = poolAmountIn currently staked.

### `isDepositAllowed(uint256 depositAmt)`
Check whether the given `depositAmt` is an acceptable amount by the pool?.
        @param depositAmt Amount of tokens (i.e loanAsset type) is user willing to deposit.

### `setLiquidityCap(uint256 newLiquidityCap)`
Set `liquidityCap`, Only allowed by the pool delegate.
        @param newLiquidityCap New liquidity cap value.

### `deposit(uint256 amt)`
Liquidity providers can deposit LiqudityAsset into the LiquidityLocker, minting FDTs.
        @param amt The amount of LiquidityAsset to deposit, in wei.

### `withdraw(uint256 amt)`
Liquidity providers can withdraw LiqudityAsset from the LiquidityLocker, burning FDTs.
        @param amt The amount of LiquidityAsset to withdraw.

### `fundLoan(address loan, address dlFactory, uint256 amt)`
Fund a loan for amt, utilize the supplied dlFactory for debt lockers.
        @param  loan      Address of the loan to fund.
        @param  dlFactory The debt locker factory to utilize.
        @param  amt       Amount to fund the loan.

### `claim(address loan, address dlFactory)`
Claim available funds for loan through specified debt locker factory.
        @param  loan      Address of the loan to claim from.
        @param  dlFactory The debt locker factory (always maps to a single debt locker).
        @return [0] = Total amount claimed.
                [1] = Interest portion claimed.
                [2] = Principal portion claimed.
                [3] = Fee portion claimed.
                [4] = Excess portion claimed.
                [5] = Liquidation portion claimed.

### `deactivate(uint256 confirmation)`
Pool Delegate triggers deactivation, permanently shutting down the pool.
        @param confirmation Pool delegate must supply the number 86 for this function to deactivate, a simple confirmation.

### `calcWithdrawPenalty(uint256 amt, address who)`
Calculate the amount of funds to deduct from total claimable amount based on how
             the effective length of time a user has been in a pool. This is a linear decrease
             until block.timestamp - depositDate[who] >= penaltyDelay, after which it returns 0.
        @param  amt Total claimable amount 
        @param  who Address of user claiming
        @return penalty Total penalty

### `setPenaltyDelay(uint256 _penaltyDelay)`
Set the amount of time required to recover 100% of claimable funds 
             (i.e. calcWithdrawPenalty = 0)
        @param _penaltyDelay Effective time needed in pool for user to be able to claim 100% of funds

### `setPrincipalPenalty(uint256 _newPrincipalPenalty)`
Allowing delegate/pool manager to set the principal penalty.
        @param _newPrincipalPenalty New principal penalty percentage (in bips) that corresponds to withdrawal amount.

### `setLockupPeriod(uint256 _newLockupPeriod)`
Allowing delegate/pool manager to set the lockup period.
        @param _newLockupPeriod New lockup period used to restrict the withdrawals.

### `setAllowlistStakeLocker(address user, bool status)`
Update user status on StakeLocker allowlist.
        @param user   The address to set status for.
        @param status The status of user on allowlist.

### `claimableFunds(address lp)`
View claimable balance from LiqudityLocker (reflecting deposit + gain/loss).
        @param lp Liquidity Provider to check claimableFunds for 
        @return [0] = Total amount claimable.
                [1] = Principal amount claimable.
                [2] = Interest amount claimable.

### `withdrawFunds()`
Withdraws all claimable interest from the `liquidityLocker` for a user using `interestSum` accounting.

## <u>Events</u>

### `LoanFunded(address loan, address debtLocker, uint256 amountFunded)`
No description

### `BalanceUpdated(address who, address token, uint256 balance)`
No description

### `Claim(address loan, uint256 interest, uint256 principal, uint256 fee)`
No description

### `DefaultSuffered(address loan, uint256 defaultSuffered, uint256 bptsBurned, uint256 bptsReturned, uint256 liquidityAssetRecoveredFromBurn)`
No description
