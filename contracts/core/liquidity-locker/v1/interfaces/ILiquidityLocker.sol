// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title LiquidityLocker holds custody of Liquidity Asset tokens for a given Pool.
interface ILiquidityLocker {

    /**
        @dev The Pool contract address that owns this LiquidityLocker.
     */
    function pool() external view returns (address);

    /**
        @dev The Liquidity Asset which this LiquidityLocker will escrow.
     */
    function liquidityAsset() external view returns (IERC20);

    /**
        @dev   Transfers amount of Liquidity Asset to a destination account. 
        @dev   Only the Pool can call this function. 
        @param destination The destination to transfer Liquidity Asset to.
        @param amount      The amount of Liquidity Asset to transfer.
     */
    function transfer(address destination, uint256 amount) external;

    /**
        @dev   Funds a Loan using available assets in this LiquidityLocker. 
        @dev   Only the Pool can call this function. 
        @param loan       The Loan to fund.
        @param debtLocker The DebtLocker that will escrow debt tokens.
        @param amount     The amount of Liquidity Asset to fund the Loan for.
     */
    function fundLoan(address loan, address debtLocker, uint256 amount) external;

}
