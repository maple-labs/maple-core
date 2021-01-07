// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
import "./DebtLocker.sol";

contract DebtLockerFactory {

    mapping(address => address) public owner;     // owner[locker] = Owner of the collateral locker.
    mapping(address => bool)    public isLocker;  // True if debtLocker was created in this factory, otherwise false.

    /// @notice Deploy a new debt locker.
    /// @param loan The loan this debt locker is hold debt tokens for.
    /// @return Address of the deployed debt locker.
    function newLocker(address loan) external returns (address) {
        address locker   = address(new DebtLocker(loan, msg.sender));
        owner[locker]    = msg.sender;
        isLocker[locker] = true;
        return locker;
    }
    
}
