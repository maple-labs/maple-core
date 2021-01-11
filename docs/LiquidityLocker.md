

## Functions:
[`constructor(address _liquidityAsset, address _owner)`](#LiquidityLocker-constructor-address-address-)
[`transfer(address dst, uint256 amt)`](#LiquidityLocker-transfer-address-uint256-)
[`fundLoan(address loan, address debtLocker, uint256 amt)`](#LiquidityLocker-fundLoan-address-address-uint256-)


## <u>Functions</u>

### `constructor(address _liquidityAsset, address _owner)`
No description

### `transfer(address dst, uint256 amt)`
Transfers amt of liquidityAsset to dst.
        @param  dst Desintation to transfer liquidityAsset to.
        @param  amt Amount of liquidityAsset to transfer.

### `fundLoan(address loan, address debtLocker, uint256 amt)`
Fund a loan using available assets in this liquidity locker.
        @param  loan       The loan to fund.
        @param  debtLocker The locker that will escrow debt tokens.
        @param  amt        Amount of liquidityAsset to fund the loan for.

## <u>Events</u>
