

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
No description

### `finalize()`
No description

### `getInitialStakeRequirements()`
No description

### `deposit(uint256 amt)`
No description

### `withdraw(uint256 amt)`
No description

### `fundLoan(address loan, address dlFactory, uint256 amt)`
No description

### `claim(address loan, address dlFactory)`
No description

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
