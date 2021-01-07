// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
import "./DebtLocker.sol";

contract DebtLockerFactory {

    // TODO: Identify why we have owner and lockers as two data structures for same purpose.

    mapping(address => address) private owner;  // Mapping data structure for owners of staked asset lockers.
    mapping(address => bool)    private isLocker;    // Mapping to tell us if an address is a locker

    address[] public lockers;

    // @notice Creates a new locker.
    // @param _liquidAsset The address of the dividend token, also the primary investment asset of the LP.
    // @return The address of the newly created locker.
    function newLocker(address loan) external returns (address) {
        address locker   = address(new DebtLocker(loan, msg.sender));
        owner[locker]    = address(msg.sender);
        isLocker[locker] = true;
        lockers.push(locker);
        return locker;
    }

    // @notice Returns the address of the locker's parent liquidity pool.
    // @param locker The address of the locker.
    // @return The owner of the locker.
    function getPool(address locker) public view returns (address) {
        return owner[locker];
    }

    // @notice returns true if address is a liwuid asset locker
    // @param _addy address to test
    // @return true if _addy is liquid asset locker
    function isDebtLocker(address locker) external view returns (bool) {
        return isLocker[locker];
    }
}
