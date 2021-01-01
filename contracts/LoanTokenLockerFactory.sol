// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
import "./LoanTokenLocker.sol";

contract LoanTokenLockerFactory {
    // Mapping data structure for owners of staked asset lockers.
    mapping(address => address) private lockerPool;

    //Mapping to tell us if an address is a locker
    mapping(address => bool) private isLocker;

    address[] public lockers;

    event DebugAdd(string, address);

    // @notice Creates a new locker.
    // @param _liquidAsset The address of the dividend token, also the primary investment asset of the LP.
    // @return The address of the newly created locker.
    function newLocker(address _loanToken) external returns (address) {
        address _liquidityPoolAddress = address(msg.sender);
        address _tokenLocker = address(new LoanTokenLocker(_loanToken, _liquidityPoolAddress));
        emit DebugAdd("_liquidityPoolAddress", _liquidityPoolAddress);
        emit DebugAdd("_tokenLocker", _tokenLocker);
        emit DebugAdd("msg.sender", msg.sender);
        lockerPool[_tokenLocker] = _liquidityPoolAddress;
        isLocker[_tokenLocker] = true;
        lockers.push(_tokenLocker);
        return _tokenLocker;
    }

    // @notice Returns the address of the locker's parent liquidity pool.
    // @param _locker The address of the locker.
    // @return The owner of the locker.
    function getPool(address _locker) public view returns (address) {
        return lockerPool[_locker];
    }

    // @notice returns true if address is a liwuid asset locker
    // @param _addy address to test
    // @return true if _addy is liquid asset locker
    function isLoanTokenLocker(address _locker) external view returns (bool) {
        return isLocker[_locker];
    }
}
