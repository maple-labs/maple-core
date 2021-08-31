// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

interface IBFactory {

    function isBPool(address) external view returns (bool);

    function newBPool() external returns (address);

}
