// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title CollateralLocker holds custody of Collateral Asset for Loans.
interface ICollateralLocker {

    /**
        @dev The address the Collateral Asset the Loan is collateralized with.
     */
    function collateralAsset() external view returns (IERC20);

    /**
        @dev The Loan contract address this CollateralLocker is attached to.
     */
    function loan() external view returns (address);

    /**
        @dev   Transfers `amt` of Collateral Asset to `dst`. 
        @dev   Only the Loan can call this function. 
        @param dst The destination to transfer Collateral Asset to.
        @param amt The amount of Collateral Asset to transfer.
     */
    function pull(address dst, uint256 amt) external;

}
