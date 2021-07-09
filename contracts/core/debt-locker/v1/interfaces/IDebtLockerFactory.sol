// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { ISubFactory } from "../../../subfactory/v1/interfaces/ISubFactory.sol";

/// @title DebtLockerFactory instantiates DebtLockers.
interface IDebtLockerFactory is ISubFactory {

    /**
        @dev   Emits an event indicating a DebtLocker was created.
        @param owner      The owner of the DebtLocker.
        @param debtLocker The address of the DebtLocker.
        @param loan       The Loan tied to the DebtLocker.
     */
    event DebtLockerCreated(address indexed owner, address debtLocker, address loan);

    /**
        @param  debtLocker The address of a DebtLocker.
        @return The address of the owner of DebtLocker at `debtLocker`.
     */
    function owner(address debtLocker) external view returns (address);

    /**
        @param  debtLocker Some address.
        @return Whether `debtLocker` is a DebtLocker.
     */
    function isLocker(address debtLocker) external view returns (bool);

    /**
        @dev The type of the factory (i.e FactoryType::DEBT_LOCKER_FACTORY).
     */
    function factoryType() external override pure returns (uint8);

    /**
        @dev    Instantiates a DebtLocker. 
        @dev    It emits a `DebtLockerCreated` event. 
        @param  loan       The Loan this DebtLocker will be tied to.
        @return debtLocker The address of the instantiated DebtLocker.
     */
    function newLocker(address loan) external returns (address debtLocker);

}
