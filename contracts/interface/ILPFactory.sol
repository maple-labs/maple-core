pragma solidity 0.7.0;

interface ILPFactory {
    function isLPool(address _addy) external view returns (bool);
}
