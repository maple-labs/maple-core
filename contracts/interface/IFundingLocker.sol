pragma solidity 0.7.0;

interface IFundingLocker {
	function fundingAsset() external view returns (address);
	function loanVault() external view returns (address);
	function pull(address, uint) external view returns (bool);
	function drain() external view returns (bool);
}
