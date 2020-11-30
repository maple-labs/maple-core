pragma solidity 0.7.0;

interface IStakeLockerFactory {
    function newLocker(
        address _stakedAsset,
        address _liquidAsset,
        address _globals
    ) external returns (address);
}