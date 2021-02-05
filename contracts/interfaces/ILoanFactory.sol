// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

interface ILoanFactory {
    function isLoan(address) external view returns (bool);
    function loans(uint256)  external view returns (address);
    function globals()       external view returns (address);
    
    /**
        @dev Create a new Loan.
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
    */
    function createLoan(
        address loanAsset,
        address collateralAsset,
        address flFactory,
        address clFactory,
        uint256[6] memory specs,
        address[3] memory calcs
    ) external returns (address);
}
