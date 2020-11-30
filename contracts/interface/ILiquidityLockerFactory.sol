pragma solidity 0.7.0;

interface ILiquidityLockerFactory {
    function newLocker(address _liquidAsset) external returns (address);

    function isLiquidAssetLocker(address _locker) external returns (bool);

    function fundLoan(address _loanVault, uint256 _amt) external;
}
