// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { IERC20 } from "../../../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { IExtendedFDT } from "../../../funds-distribution-token/v1/interfaces/IExtendedFDT.sol";

/// @title StakeLockerFDT inherits ExtendedFDT and accounts for gains/losses for Stakers.
interface IStakeLockerFDT is IExtendedFDT {

    /**
        @dev The ERC-2222 Funds Token.
     */
    function fundsToken() external view returns (IERC20);

    /**
        @dev The sum of all unrecognized losses.
     */
    function bptLosses() external view returns (uint256);

    /**
        @dev The amount of losses present and accounted for in this contract.
     */
    function lossesBalance() external view returns (uint256);

    /**
        @dev The amount of `fundsToken` (Liquidity Asset) currently present and accounted for in this contract.
     */
    function fundsTokenBalance() external view returns (uint256);

}
