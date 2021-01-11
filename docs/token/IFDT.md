

## Functions:
[`withdrawableFundsOf(address owner)`](#IFDT-withdrawableFundsOf-address-)
[`withdrawFunds()`](#IFDT-withdrawFunds--)

## Events:
[`FundsDistributed(address by, uint256 fundsDistributed)`](#IFDT-FundsDistributed-address-uint256-)
[`FundsWithdrawn(address by, uint256 fundsWithdrawn)`](#IFDT-FundsWithdrawn-address-uint256-)

## <u>Functions</u>

### `withdrawableFundsOf(address owner)`
Returns the total amount of funds a given address is able to withdraw currently.


### Parameters:
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; `owner`: Address of FDT holder


### Returns:
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; A uint256 representing the available funds for a given account

### `withdrawFunds()`
Withdraws all available funds for a FDT holder.

## <u>Events</u>

### `FundsDistributed(address by, uint256 fundsDistributed)`
This event emits when new funds are distributed


### Parameters:
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; `by`: the address of the sender who distributed funds

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; `fundsDistributed`: the amount of funds received for distribution

### `FundsWithdrawn(address by, uint256 fundsWithdrawn)`
This event emits when distributed funds are withdrawn by a token holder.


### Parameters:
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; `by`: the address of the receiver of funds

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; `fundsWithdrawn`: the amount of funds that were withdrawn
