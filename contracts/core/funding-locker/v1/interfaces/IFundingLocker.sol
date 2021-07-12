// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "../../../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title FundingLocker holds custody of Liquidity Asset tokens during the funding period of a Loan.
interface IFundingLocker {

    /**
        @dev The asset the Loan was funded with.
    */
    function liquidityAsset() external view returns (IERC20);

    /**
        @dev The Loan this FundingLocker has funded.
    */
    function loan() external view returns (address);

    /**
        @dev   Transfers `amt` of Liquidity Asset to `dst`. 
        @dev   Only the Loan can call this function. 
        @param dst The destination to transfer Liquidity Asset to.
        @param amt The amount of Liquidity Asset to transfer.
    */
    function pull(address dst, uint256 amt) external;

    /**
        @dev Transfers entire amount of Liquidity Asset held in escrow to the Loan. 
        @dev Only the Loan can call this function. 
    */
    function drain() external;

}
