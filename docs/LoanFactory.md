

## Functions:
[`constructor(address _globals)`](#LoanFactory-constructor-address-)
[`setGlobals(address newGlobals)`](#LoanFactory-setGlobals-address-)
[`createLoan(address loanAsset, address collateralAsset, address flFactory, address clFactory, uint256[6] specs, address[3] calcs)`](#LoanFactory-createLoan-address-address-address-address-uint256-6--address-3--)

## Events:
[`LoanCreated(string tUUID, address loan, address borrower, address loanAsset, address collateralAsset, address collateralLocker, address fundingLocker, uint256[6] specs, address[3] calcs, string name, string symbol)`](#LoanFactory-LoanCreated-string-address-address-address-address-address-address-uint256-6--address-3--string-string-)

## <u>Functions</u>

### `constructor(address _globals)`
No description

### `setGlobals(address newGlobals)`
Update the maple globals contract
        @param  newGlobals Address of new maple globals contract

### `createLoan(address loanAsset, address collateralAsset, address flFactory, address clFactory, uint256[6] specs, address[3] calcs)`
Create a new Loan.
        @param  loanAsset       Asset the loan will raise funding in.
        @param  collateralAsset Asset the loan will use as collateral.
        @param  flFactory       The factory to instantiate a Funding Locker from.
        @param  clFactory       The factory to instantiate a Collateral Locker from.
        @param  specs           Contains specifications for this loan.
                specs[0] = apr
                specs[1] = termDays
                specs[2] = paymentIntervalDays
                specs[3] = requestAmount
                specs[4] = collateralRatio
                specs[5] = fundingPeriodDays
        @param  calcs           The calculators used for the loan.
                calcs[0] = repaymentCalc
                calcs[1] = lateFeeCalc
                calcs[2] = premiumCalc
        @return Address of the instantiated Loan.

## <u>Events</u>

### `LoanCreated(string tUUID, address loan, address borrower, address loanAsset, address collateralAsset, address collateralLocker, address fundingLocker, uint256[6] specs, address[3] calcs, string name, string symbol)`
No description
