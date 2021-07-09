// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

/// @title SubFactory creates instances downstream of another factory.
interface ISubFactory {

    /**
        @dev The type of the factory
     */
    function factoryType() external pure returns (uint8);

}
