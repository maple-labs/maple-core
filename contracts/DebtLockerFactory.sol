// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "./DebtLocker.sol";

/// @title DebtLockerFactory instantiates DebtLockers.
contract DebtLockerFactory {

    mapping(address => address) public owner;     // Mapping of DebtLocker addresses to their owner (i.e owner[locker] = Owner of the DebtLocker).
    mapping(address => bool)    public isLocker;  // True only if a DebtLocker was created by this factory.

    uint8 public constant factoryType = 1;  // i.e LockerFactoryTypes::DEBT_LOCKER_FACTORY

    event DebtLockerCreated(address indexed owner, address debtLocker, address loan);

    /**
        @dev    Instantiates a DebtLocker.
        @dev    It emits a `DebtLockerCreated` event.
        @param  loan       The Loan this DebtLocker will escrow tokens for.
        @return debtLocker Address of the instantiated DebtLocker.
    */
    function newLocker(address loan) external returns (address debtLocker) {
        debtLocker           = address(new DebtLocker(loan, msg.sender));
        owner[debtLocker]    = msg.sender;
        isLocker[debtLocker] = true;

        emit DebtLockerCreated(msg.sender, debtLocker, loan);
    }

}
