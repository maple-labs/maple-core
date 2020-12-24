// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

interface IFundingLockerFactory {
    function newLocker(address) external returns (address);

    function getOwner(address) external view returns (address);

    function verifyLocker(address) external view returns (bool);
}
