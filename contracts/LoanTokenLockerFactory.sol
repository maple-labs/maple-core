pragma solidity 0.7.0;
import "./LoanTokenLocker.sol";

contract LoanTokenLockerFactory {
    // Mapping data structure for owners of staked asset lockers.
    mapping(address => address) private lockerPool;

    //Mapping to tell us if an address is a locker
    mapping(address => bool) private isLocker;

    // @notice Creates a new locker.
    // @param _liquidAsset The address of the dividend token, also the primary investment asset of the LP.
    // @return The address of the newly created locker.
    // TODO: Consider whether this needs to be external or public.
    //TODO ADD MODIFIER LETTING ONLY LIQUIDITY POOLS RUN THIS (not critical, but good)
    function newLocker() external returns (address) {
        address _LPaddy = address(msg.sender);
        address _tokenLocker = address(new LoanTokenLocker(_LPaddy));
        lockerPool[_tokenLocker] = _LPaddy;
        isLocker[_tokenLocker] = true;
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
