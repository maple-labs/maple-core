// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { IMapleGlobals } from "core/globals/v1/interfaces/IMapleGlobals.sol";

/// @title LoanFactory instantiates Loans.
interface ILoanFactory {

    /**
        @dev   Emits an event indicating a LoanFactoryAdmin was allowed.
        @param loanFactoryAdmin The address of a LoanFactoryAdmin.
        @param allowed          Whether `loanFactoryAdmin` is allowed as an admin of the LoanFactory.
     */
    event LoanFactoryAdminSet(address indexed loanFactoryAdmin, bool allowed);

    /**
        @dev   Emits an event indicating a Loan was created.
        @param loan             The address of the Loan.
        @param borrower         The Borrower.
        @param liquidityAsset   The asset the Loan will raise funding in.
        @param collateralAsset  The asset the Loan will use as collateral.
        @param collateralLocker The address of the Collateral Locker.
        @param fundingLocker    The address of the Funding Locker.
        @param specs            The specifications for the Loan. 
                                    [0] => apr, 
                                    [1] => termDays, 
                                    [2] => paymentIntervalDays, 
                                    [3] => requestAmount, 
                                    [4] => collateralRatio. 
        @param calcs            The calculators used for the Loan. 
                                    [0] => repaymentCalc, 
                                    [1] => lateFeeCalc, 
                                    [2] => premiumCalc. 
        @param name             The name of the Loan FDTs.
        @param symbol           The symbol of the Loan FDTs.
     */
    event LoanCreated(
        address loan,
        address indexed borrower,
        address indexed liquidityAsset,
        address collateralAsset,
        address collateralLocker,
        address fundingLocker,
        uint256[5] specs,
        address[3] calcs,
        string name,
        string symbol
    );

    /**
        @dev The Factory type of `CollateralLockerFactory`.
     */
    function CL_FACTORY() external view returns (uint8);

    /**
        @dev The Factory type of `FundingLockerFactory`.
     */
    function FL_FACTORY() external view returns (uint8);

    /**
        @dev The Calc type of `RepaymentCalc`.
     */
    function INTEREST_CALC_TYPE() external view returns (uint8);

    /**
        @dev The Calc type of `LateFeeCalc`.
     */
    function LATEFEE_CALC_TYPE() external view returns (uint8);

    /**
        @dev The Calc type of `PremiumCalc`.
     */
    function PREMIUM_CALC_TYPE() external view returns (uint8);

    /**
        @dev The instance of the MapleGlobals.
     */
    function globals() external view returns (IMapleGlobals);

    /**
        @dev The incrementor for number of Loans created.
     */
    function loansCreated() external view returns (uint256);

    /**
        @param  index The index of a Loan.
        @return The address of the Loan at `index`.
     */
    function loans(uint256 index) external view returns (address);

    /**
        @param  loan The address of a Loan.
        @return Whether `loan` is a Loan.
     */
    function isLoan(address loan) external view returns (bool);

    /**
        @param  admin The address of a LoanFactoryAdmin.
        @return Whether `admin` has permission to do certain operations in case of disaster management.
     */
    function loanFactoryAdmins(address admin) external view returns (bool);

    /**
        @dev   Sets MapleGlobals. 
        @dev   Only the Governor can call this function. 
        @param newGlobals Address of new MapleGlobals.
     */
    function setGlobals(address newGlobals) external;

    /**
        @dev    Create a new Loan. 
        @dev    It emits a `LoanCreated` event. 
        @param  liquidityAsset  The asset the Loan will raise funding in.
        @param  collateralAsset The asset the Loan will use as collateral.
        @param  flFactory       The factory to instantiate a FundingLocker from.
        @param  clFactory       The factory to instantiate a CollateralLocker from.
        @param  specs           The specifications for the Loan. 
                                    [0] => apr, 
                                    [1] => termDays, 
                                    [2] => paymentIntervalDays, 
                                    [3] => requestAmount, 
                                    [4] => collateralRatio. 
        @param  calcs           The calculators used for the Loan. 
                                    [0] => repaymentCalc, 
                                    [1] => lateFeeCalc, 
                                    [2] => premiumCalc. 
        @return loanAddress     Address of the instantiated Loan.
     */
    function createLoan(
        address liquidityAsset,
        address collateralAsset,
        address flFactory,
        address clFactory,
        uint256[5] memory specs,
        address[3] memory calcs
    ) external returns (address);

    /**
        @dev   Sets a LoanFactory Admin. Only the Governor can call this function.
        @dev   It emits a `LoanFactoryAdminSet` event.
        @param loanFactoryAdmin An address being allowed or disallowed as a LoanFactory Admin.
        @param allowed          The status of `loanFactoryAdmin` as an Admin.
     */
    function setLoanFactoryAdmin(address loanFactoryAdmin, bool allowed) external;

    /**
        @dev Triggers paused state. 
        @dev Halts functionality for certain functions. 
        @dev Only the Governor or a LoanFactory Admin can call this function.
     */
    function pause() external;

    /**
        @dev Triggers unpaused state. 
        @dev Restores functionality for certain functions. 
        @dev Only the Governor or a LoanFactory Admin can call this function.
     */
    function unpause() external;

}
