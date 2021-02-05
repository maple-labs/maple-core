

## Functions:
[`constructor(string name, string symbol, address _fundsToken)`](#FDT-constructor-string-string-address-)
[`withdrawableFundsOf(address _owner)`](#FDT-withdrawableFundsOf-address-)
[`withdrawnFundsOf(address _owner)`](#FDT-withdrawnFundsOf-address-)
[`accumulativeFundsOf(address _owner)`](#FDT-accumulativeFundsOf-address-)
[`withdrawFunds()`](#FDT-withdrawFunds--)
[`withdrawFundsOnBehalf(address user)`](#FDT-withdrawFundsOnBehalf-address-)
[`updateFundsReceived()`](#FDT-updateFundsReceived--)


## <u>Functions</u>

### `constructor(string name, string symbol, address _fundsToken)`
No description

### `withdrawableFundsOf(address _owner)`
View the amount of funds that an address can withdraw.


### Parameters:
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; `_owner`: The address of a token holder.


### Returns:
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; The amount funds that `_owner` can withdraw.

### `withdrawnFundsOf(address _owner)`
View the amount of funds that an address has withdrawn.


### Parameters:
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; `_owner`: The address of a token holder.


### Returns:
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; The amount of funds that `_owner` has withdrawn.

### `accumulativeFundsOf(address _owner)`
View the amount of funds that an address has earned in total.
accumulativeFundsOf(_owner) = withdrawableFundsOf(_owner) + withdrawnFundsOf(_owner)
= (pointsPerShare * balanceOf(_owner) + pointsCorrection[_owner]) / pointsMultiplier


### Parameters:
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; `_owner`: The address of a token holder.


### Returns:
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; The amount of funds that `_owner` has earned in total.

### `withdrawFunds()`
Withdraws all available funds for a token holder

### `withdrawFundsOnBehalf(address user)`
Withdraws all available funds for a token holder, on behalf of token holder

### `updateFundsReceived()`
Register a payment of funds in tokens. May be called directly after a deposit is made.
Calls _updateFundsTokenBalance(), whereby the contract computes the delta of the previous and the new
funds token balance and increments the total received funds (cumulative) by delta by calling _registerFunds()

## <u>Events</u>
