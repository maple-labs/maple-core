// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "./interfaces/IDebtLockerFactory.sol";

import "./DebtLocker.sol";

/// @title DebtLockerFactory instantiates DebtLockers.
contract DebtLockerFactory is IDebtLockerFactory {

    mapping(address => address) public override owner;     // Owners of respective DebtLockers.
    mapping(address => bool)    public override isLocker;  // True only if a DebtLocker was created by this factory.

    uint8 public override constant factoryType = 1;

    function newLocker(address loan) external override returns (address debtLocker) {
        debtLocker           = address(new DebtLocker(loan, msg.sender));
        owner[debtLocker]    = msg.sender;
        isLocker[debtLocker] = true;

        emit DebtLockerCreated(msg.sender, debtLocker, loan);
    }

}
