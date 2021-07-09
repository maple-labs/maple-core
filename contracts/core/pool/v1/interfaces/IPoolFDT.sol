// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { IExtendedFDT } from "core/funds-distribution-token/v1/interfaces/IExtendedFDT.sol";

/// @title PoolFDT inherits ExtendedFDT and accounts for gains/losses for Liquidity Providers.
interface IPoolFDT is IExtendedFDT {

    /**
        @dev The sum of all withdrawable interest.
     */
    function interestSum() external view returns (uint256);

    /**
        @dev The sum of all unrecognized losses.
     */
    function poolLosses() external view returns (uint256);

    /**
        @dev The amount of earned interest present and accounted for in this contract.
     */
    function interestBalance() external view returns (uint256);

    /**
        @dev The amount of losses present and accounted for in this contract.
     */
    function lossesBalance() external view returns (uint256);

}
