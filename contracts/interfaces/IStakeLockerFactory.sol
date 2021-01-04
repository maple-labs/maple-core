// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

interface IStakeLockerFactory {
    function newLocker(
        address _stakeAsset,
        address _liquidityAsset,
        address _globals,
	string memory _LPSymbol
    ) external returns (address);
}
