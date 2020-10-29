

## Functions:
[`withdrawableFundsOf(address _owner)`](#FundsDistributionToken-withdrawableFundsOf-address-)
[`withdrawnFundsOf(address _owner)`](#FundsDistributionToken-withdrawnFundsOf-address-)
[`accumulativeFundsOf(address _owner)`](#FundsDistributionToken-accumulativeFundsOf-address-)


## <u>Functions</u>

### `withdrawableFundsOf(address _owner)`
No description

### Parameters:
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; `_owner`: The address of a token holder.


### Returns:
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; The amount funds that `_owner` can withdraw.

### `withdrawnFundsOf(address _owner)`
No description

### Parameters:
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; `_owner`: The address of a token holder.


### Returns:
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; The amount of funds that `_owner` has withdrawn.

### `accumulativeFundsOf(address _owner)`
accumulativeFundsOf(_owner) = withdrawableFundsOf(_owner) + withdrawnFundsOf(_owner)
= (pointsPerShare * balanceOf(_owner) + pointsCorrection[_owner]) / pointsMultiplier


### Parameters:
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; `_owner`: The address of a token holder.


### Returns:
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; The amount of funds that `_owner` has earned in total.

## <u>Events</u>
