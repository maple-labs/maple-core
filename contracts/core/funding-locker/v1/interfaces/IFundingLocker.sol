// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

/// @title FundingLocker holds custody of Liquidity Asset tokens during the funding period of a Loan.
interface IFundingLocker {

    /**
        @dev The asset the Loan was funded with.
    */
    function liquidityAsset() external view returns (address);

    /**
        @dev The Loan this FundingLocker has funded.
    */
    function loan() external view returns (address);

    /**
        @dev   Transfers `amount` of Liquidity Asset to `destination`. 
        @dev   Only the Loan can call this function. 
        @param destination The destination to transfer Liquidity Asset to.
        @param amount      The amount of Liquidity Asset to transfer.
    */
    function pull(address destination, uint256 amount) external;

    /**
        @dev Transfers entire amount of Liquidity Asset held in escrow to the Loan. 
        @dev Only the Loan can call this function. 
    */
    function drain() external;

}
