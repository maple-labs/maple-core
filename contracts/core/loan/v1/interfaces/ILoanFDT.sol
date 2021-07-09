// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { IERC20 } from  "../../../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { IBasicFDT } from "../../../funds-distribution-token/v1/interfaces/IBasicFDT.sol";

interface ILoanFDT is IBasicFDT {

    /**
        @dev The `fundsToken` (dividends).
     */
    function fundsToken() external view returns (IERC20);

    /**
        @dev The amount of `fundsToken` (Liquidity Asset) currently present and accounted for in this contract.
     */
    function fundsTokenBalance() external view returns (uint256);

    /**
        @dev Withdraws all available funds for a token holder.
    */
    function withdrawFunds() external override;
}
