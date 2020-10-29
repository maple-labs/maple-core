

## Functions:
[`constructor(string name, string symbol, contract IERC20 _fundsToken)`](#MapleToken-constructor-string-string-contract-IERC20-)
[`withdrawFunds()`](#MapleToken-withdrawFunds--)
[`updateFundsReceived()`](#MapleToken-updateFundsReceived--)


## <u>Functions</u>

### `constructor(string name, string symbol, contract IERC20 _fundsToken)`
No description

### `withdrawFunds()`
No description

### `updateFundsReceived()`
Calls _updateFundsTokenBalance(), whereby the contract computes the delta of the previous and the new 
funds token balance and increments the total received funds (cumulative) by delta by calling _registerFunds()

## <u>Events</u>
