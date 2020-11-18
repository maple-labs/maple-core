// SPDX-License-Identifier: MIT

pragma solidity 0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./Token/IFundsDistributionToken.sol";
import "./Token/FundsDistributionToken.sol";
import "./Math/CalcBPool.sol";
import "./interface/IBPool.sol";
import "./interface/IGlobals.sol";
import "./LiquidAssetLockerFactory.sol";

// @title LP is the core liquidity pool contract.
contract LoanVault is IFundsDistributionToken, FundsDistributionToken {

    using SafeMathInt for int256;
    using SignedSafeMath for int256;
    using SafeMath for uint256;

    // The fundsToken (dividends) and assetRequested.
    IERC20 private fundsToken;

    // The fundsToken (dividends) and assetRequested.
    IERC20 private IRequestedAsset;

    // The collateral asset for this loan vault.
    IERC20 private ICollateralAsset;

    // The maple globals contract.
    IGlobals private MapleGlobals;

    /// @notice The amount of fundsToken (assetRequested) currently present and accounted for in this contract.
    uint256 public fundsTokenBalance;

    /// @notice The asset deposited by lenders into the InvestmentLocker, when funding this loan.
    address public assetRequested;

    /// @notice The asset deposited by borrower into the CollateralLocker, for collateralizing this loan.
    address public assetCollateral;

    /// @notice The borrower of this loan, responsible for repayments.
    address public borrower;

    /// @notice Constructor for loan vault.
    /// @param _assetRequested The asset borrower is requesting funding in.
    /// @param _assetCollateral The asset provided as collateral by the borrower.
    /// @param name The name of the loan vault's token (minted when investors fund the loan).
    /// @param symbol The ticker of the loan vault's token.
    /// @param _mapleGlobals Address of the MapleGlobals.sol contract.
    constructor(
        address _assetRequested,
        address _assetCollateral,
        string memory name,
        string memory symbol,
        address _mapleGlobals
    ) FundsDistributionToken(name, symbol) {
        
        require(
            address(_assetRequested) != address(0),
            "FDT_ERC20Extension: INVALID_FUNDS_TOKEN_ADDRESS"
        );

        assetRequested = _assetRequested;
        assetCollateral = _assetCollateral;
        IRequestedAsset = IERC20(_assetRequested);
        fundsToken = IRequestedAsset;
        MapleGlobals = IGlobals(_mapleGlobals);
        borrower = tx.origin;
    }

}
