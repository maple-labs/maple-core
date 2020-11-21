pragma solidity 0.7.0;

interface ILiquidityPool {
    function poolDelegate() external view returns (address);

    function isDefunct() external view returns (bool);

    function isFinalized() external view returns (bool);
}
