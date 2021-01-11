

## Functions:
[`constructor(address _globals, address _flFactory, address _clFactory)`](#LoanFactory-constructor-address-address-address-)
[`createLoan(address loanAsset, address collateralAsset, uint256[6] specs, address[3] calcs)`](#LoanFactory-createLoan-address-address-uint256-6--address-3--)
[`setFundingLockerFactory(address _flFactory)`](#LoanFactory-setFundingLockerFactory-address-)
[`setCollateralLockerFactory(address _clFactory)`](#LoanFactory-setCollateralLockerFactory-address-)

## Events:
[`LoanCreated(string tUUID, address loan, address borrower, address loanAsset, address collateralAsset, address collateralLocker, address fundingLocker, uint256[6] specs, address[3] calcs, string name, string symbol)`](#LoanFactory-LoanCreated-string-address-address-address-address-address-address-uint256-6--address-3--string-string-)

## <u>Functions</u>

### `constructor(address _globals, address _flFactory, address _clFactory)`
No description

### `createLoan(address loanAsset, address collateralAsset, uint256[6] specs, address[3] calcs)`
Create a new Loan.
        @param  loanAsset       Asset the loan will raise funding in.
        @param  collateralAsset Asset the loan will use as collateral.
        @param  specs           Contains specifications for this loan.
                specs[0] = apr
                specs[1] = termDays
                specs[2] = paymentIntervalDays
                specs[3] = minRaise
                specs[4] = collateralRatio
                specs[5] = fundingPeriodDays
        @param  calcs           The calculators used for the loan.
                calcs[0] = repaymentCalc
                calcs[1] = lateFeeCalc
                calcs[2] = premiumCalc
        @return Address of the instantiated Loan.

### `setFundingLockerFactory(address _flFactory)`
Governor can adjust the flFactory.
        @param  _flFactory The new flFactory address.

### `setCollateralLockerFactory(address _clFactory)`
Governor can adjust the clFactory.
        @param  _clFactory The new clFactory address.

## <u>Events</u>

### `LoanCreated(string tUUID, address loan, address borrower, address loanAsset, address collateralAsset, address collateralLocker, address fundingLocker, uint256[6] specs, address[3] calcs, string name, string symbol)`
No description
