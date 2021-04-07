// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "./DebtLocker.sol";

/// @title DebtLockerFactory instantiates DebtLockers.
contract DebtLockerFactory {

    mapping(address => address) public owner;     // owner[locker] = Owner of the debt locker
    mapping(address => bool)    public isLocker;  // True if debt locker was created in this factory, otherwise false

    uint8 public constant factoryType = 1;  // i.e LockerFactoryTypes::DEBT_LOCKER_FACTORY

    /**
        @dev Instantiate a DebtLocker contract.
        @param  loan The loan this debt locker will escrow tokens for
        @return Address of the instantiated debt locker
    */
    function newLocker(address loan) external returns (address) {
        address debtLocker   = address(new DebtLocker(loan, msg.sender));
        owner[debtLocker]    = msg.sender;
        isLocker[debtLocker] = true;
        return debtLocker;
    }
}
