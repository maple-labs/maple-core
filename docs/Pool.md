

## Functions:
[`constructor(address _poolDelegate, address _liquidityAsset, address _stakeAsset, address _slFactory, address _llFactory, uint256 _stakingFee, uint256 _delegateFee, string name, string symbol, address _globals)`](#Pool-constructor-address-address-address-address-address-uint256-uint256-string-string-address-)
[`finalize()`](#Pool-finalize--)
[`getInitialStakeRequirements()`](#Pool-getInitialStakeRequirements--)
[`deposit(uint256 amt)`](#Pool-deposit-uint256-)
[`withdraw(uint256 amt)`](#Pool-withdraw-uint256-)
[`fundLoan(address loan, address dlFactory, uint256 amt)`](#Pool-fundLoan-address-address-uint256-)
[`claim(address loan, address dlFactory)`](#Pool-claim-address-address-)
[`calcInterestPenalty(uint256 interest, address who)`](#Pool-calcInterestPenalty-uint256-address-)
[`setInterestDelay(uint256 _interestDelay)`](#Pool-setInterestDelay-uint256-)
[`setPrincipalPenalty(uint256 _principalPenalty)`](#Pool-setPrincipalPenalty-uint256-)

## Events:
[`LoanFunded(address loan, address debtLocker, uint256 amountFunded)`](#Pool-LoanFunded-address-address-uint256-)
[`BalanceUpdated(address who, address token, uint256 balance)`](#Pool-BalanceUpdated-address-address-uint256-)
[`Claim(uint256 interest, uint256 principal, uint256 fee)`](#Pool-Claim-uint256-uint256-uint256-)

## <u>Functions</u>

### `constructor(address _poolDelegate, address _liquidityAsset, address _stakeAsset, address _slFactory, address _llFactory, uint256 _stakingFee, uint256 _delegateFee, string name, string symbol, address _globals)`
Constructor for a Pool.
        @param  _poolDelegate   The address that has manager privlidges for the Pool.
        @param  _liquidityAsset The asset escrowed in LiquidityLocker.
        @param  _stakeAsset     The asset escrowed in StakeLocker.
        @param  _slFactory      Factory used to instantiate StakeLocker.
        @param  _llFactory      Factory used to instantiate LiquidityLocker.
        @param  _stakingFee     Fee that stakers earn on interest, in bips.
        @param  _delegateFee    Fee that _poolDelegate earns on interest, in bips.
        @param  name            Name of pool token.
        @param  symbol          Symbol of pool token.
        @param  _globals        Globals contract address.

### `finalize()`
Finalize the pool, enabling deposits. Checks poolDelegate amount deposited to StakeLocker.

### `getInitialStakeRequirements()`
Returns information on the stake requirements.
        @return [0] = Amount of stake required.
                [1] = Current swap out value of stake present.
                [2] = If enough stake is present from Pool Delegate for finalization.
                [3] = Amount of pool shares required.
                [4] = Amount of pool shares present.

### `deposit(uint256 amt)`
Liquidity providers can deposit LiqudityAsset into the LiquidityLocker, minting FDTs.
        @param amt The amount of LiquidityAsset to deposit, in wei.

### `withdraw(uint256 amt)`
Liquidity providers can withdraw LiqudityAsset from the LiquidityLocker, burning FDTs.
        @param amt The amount of LiquidityAsset to withdraw, in wei.

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
                [5] = TODO: Liquidation portion claimed.

### `calcInterestPenalty(uint256 interest, address who)`
No description

### `setInterestDelay(uint256 _interestDelay)`
No description

### `setPrincipalPenalty(uint256 _principalPenalty)`
No description

## <u>Events</u>

### `LoanFunded(address loan, address debtLocker, uint256 amountFunded)`
No description

### `BalanceUpdated(address who, address token, uint256 balance)`
No description

### `Claim(uint256 interest, uint256 principal, uint256 fee)`
No description
