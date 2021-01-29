

## Functions:
[`constructor(address _borrower, address _loanAsset, address _collateralAsset, address _flFactory, address _clFactory, address _globals, uint256[6] specs, address[3] calcs, string tUUID)`](#Loan-constructor-address-address-address-address-address-address-uint256-6--address-3--string-)
[`fundLoan(uint256 amt, address mintTo)`](#Loan-fundLoan-uint256-address-)
[`drawdown(uint256 amt)`](#Loan-drawdown-uint256-)
[`makePayment()`](#Loan-makePayment--)
[`getNextPayment()`](#Loan-getNextPayment--)
[`makeFullPayment()`](#Loan-makeFullPayment--)
[`getFullPayment()`](#Loan-getFullPayment--)
[`collateralRequiredForDrawdown(uint256 amt)`](#Loan-collateralRequiredForDrawdown-uint256-)

## Events:
[`LoanFunded(uint256 amtFunded, address _fundedBy)`](#Loan-LoanFunded-uint256-address-)
[`BalanceUpdated(address who, address token, uint256 balance)`](#Loan-BalanceUpdated-address-address-uint256-)

## <u>Functions</u>

### `constructor(address _borrower, address _loanAsset, address _collateralAsset, address _flFactory, address _clFactory, address _globals, uint256[6] specs, address[3] calcs, string tUUID)`
Constructor for a Loan.
        @param  _borrower        Will receive the funding when calling drawdown(), is also responsible for repayments.
        @param  _loanAsset       The asset _borrower is requesting funding in.
        @param  _collateralAsset The asset provided as collateral by _borrower.
        @param  _flFactory       Factory to instantiate FundingLocker with.
        @param  _clFactory       Factory to instantiate CollateralLocker with.
        @param  _globals         The MapleGlobals contract.
        @param  specs            Contains specifications for this loan.
                specs[0] = apr
                specs[1] = termDays
                specs[2] = paymentIntervalDays
                specs[3] = requestAmount
                specs[4] = collateralRatio
                specs[5] = fundingPeriodDays
        @param  calcs            The calculators used for the loan.
                calcs[0] = repaymentCalc
                calcs[1] = lateFeeCalc
                calcs[2] = premiumCalc

### `fundLoan(uint256 amt, address mintTo)`
Fund this loan and mint debt tokens for mintTo.
        @param  amt    Amount to fund the loan.
        @param  mintTo Address that debt tokens are minted to.

### `drawdown(uint256 amt)`
Drawdown funding from FundingLocker, post collateral, and transition loanState from Funding to Active.
        @param  amt Amount of loanAsset borrower draws down, remainder is returned to Loan.

### `makePayment()`
Make the next payment for this loan.

### `getNextPayment()`
Returns information on next payment amount.
        @return [0] = Principal + Interest
                [1] = Principal 
                [2] = Interest
                [3] = Payment Due Date

### `makeFullPayment()`
Make the full payment for this loan, a.k.a. "calling" the loan.

### `getFullPayment()`
Returns information on full payment amount.
        @return [0] = Principal + Interest
                [1] = Principal 
                [2] = Interest
                [3] = Payment Due Date

### `collateralRequiredForDrawdown(uint256 amt)`
Helper for calculating collateral required to drawdown amt.
        @param  amt The amount of loanAsset to drawdown from FundingLocker.
        @return The amount of collateralAsset required to post in CollateralLocker for given drawdown amt.

## <u>Events</u>

### `LoanFunded(uint256 amtFunded, address _fundedBy)`
No description

### `BalanceUpdated(address who, address token, uint256 balance)`
No description
