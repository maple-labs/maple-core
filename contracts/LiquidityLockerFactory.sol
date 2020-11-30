pragma solidity 0.7.0;

import "./LiquidityLocker.sol";

contract LiquidityLockerFactory {

    // Mapping of LiquidityLocker contracts to owners of LiquidityLockers.
    mapping(address => address) private ownerOfLocker;

    // Mapping for validation of lockers, confirmed when initialized through this contract.
    mapping(address => bool) private isLocker;

    // TODO: Consider whether this needs to be external or public.
    // TODO: ADD MODIFIER LETTING ONLY LIQUIDITY POOLS RUN THIS (not critical, but good)
    /// @notice Creates a new LiquidityLocker.
    /// @param _liquidityAsset Address of the LiquidityAsset for the LiquidityPool.
    /// @return Address of the new LiquidityLocker.
    function newLocker(address _liquidityAsset) external returns (address) {
        address _owner = address(msg.sender);
        address _liquidityLocker = address(new LiquidityLocker(_liquidityAsset, _owner));
        ownerOfLocker[_liquidityLocker] = _owner;
        isLocker[_liquidityLocker] = true;
        return _liquidityLocker;
    }

    // @notice Returns the address of the locker's parent liquidity pool.
    // @param _locker The address of the locker.
    // @return The owner of the locker.
    function getOwner(address _locker) public view returns (address) {
        return ownerOfLocker[_locker];
    }

    /// @notice Validates if the provided address is a LiqudityLocker created through this factory.
    /// @param _locker Address of the LiquidityLocker that needs validation.
    /// @return true if _locker is a valid LiquidityLocker.
    function isLiquidityLocker(address _locker) external view returns (bool) {
        return isLocker[_locker];
    }
}
