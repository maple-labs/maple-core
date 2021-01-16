// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

/**
 * @title Contract that keeps locker factory types.
 */
contract LockerFactoryTypes {

    uint8 public constant COLLATERAL_LOCKER_FACTORY  = 0;
    uint8 public constant DEBT_LOCKER_FACTORY        = 1;
    uint8 public constant FUNDING_LOCKER_FACTORY     = 2;
    uint8 public constant LIQUIDITY_LOCKER_FACTORY   = 3;
    uint8 public constant STAKE_LOCKER_FACTORY       = 4;

}