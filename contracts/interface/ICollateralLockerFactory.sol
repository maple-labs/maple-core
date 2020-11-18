pragma solidity 0.7.0;

interface ICollateralLockerFactory {
	function newLocker(address) external view returns (address);
	function getOwner(address) external view returns (address);
	function verifyLocker(address) external view returns (bool);
}
