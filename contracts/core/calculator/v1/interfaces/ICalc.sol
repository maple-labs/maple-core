// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

/// @title Calc calculates.
interface ICalc {

    /**
        @dev The Calculator type.
     */
    function calcType() external pure returns (uint8);

    /**
        @dev The Calculator name.
     */
    function name() external pure returns (bytes32);

}
