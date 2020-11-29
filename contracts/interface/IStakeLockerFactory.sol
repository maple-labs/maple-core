interface ILPStakeLockerFactory {
    function newLocker(
        address _stakedAsset,
        address _liquidAsset,
        address _globals
    ) external returns (address);
}