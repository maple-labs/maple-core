// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { SafeMath } from "../../../../lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import { SafeERC20, IERC20 } from "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/SafeERC20.sol";

import { IERC20Details } from "../../../external-interfaces/IERC20Details.sol";
import { IUniswapRouter } from "../../../external-interfaces/IUniswapRouter.sol";

import { ICollateralLocker } from "../../../core/collateral-locker/v1/interfaces/ICollateralLocker.sol";
import { IFundingLocker } from "../../../core/funding-locker/v1/interfaces/IFundingLocker.sol";
import { IMapleGlobals } from "../../../core/globals/v1/interfaces/IMapleGlobals.sol";
import { ILateFeeCalc } from "../../../core/late-fee-calculator/v1/interfaces/ILateFeeCalc.sol";
import { ILoanFactory } from "../../../core/loan/v1/interfaces/ILoanFactory.sol";
import { IPremiumCalc } from "../../../core/premium-calculator/v1/interfaces/IPremiumCalc.sol";
import { IRepaymentCalc } from "../../../core/repayment-calculator/v1/interfaces/IRepaymentCalc.sol";

import { Util } from "../../../libraries/util/v1/Util.sol";

/// @title LoanLib is a library of utility functions used by Loan.
library LoanLib {

    using SafeMath  for uint256;
    using SafeERC20 for IERC20;

    address public constant UNISWAP_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    /********************************/
    /*** Lender Utility Functions ***/
    /********************************/

    /**
        @dev    Performs sanity checks on the data passed in Loan constructor.
        @param  globals         The instance of a MapleGlobals.
        @param  liquidityAsset  The contract address of the Liquidity Asset.
        @param  collateralAsset The contract address of the Collateral Asset.
        @param  specs           The contains specifications for this Loan.
     */
    function loanSanityChecks(IMapleGlobals globals, address liquidityAsset, address collateralAsset, uint256[5] calldata specs) external view {
        require(globals.isValidLiquidityAsset(liquidityAsset),   "L:INVALID_LIQ_ASSET");
        require(globals.isValidCollateralAsset(collateralAsset), "L:INVALID_COL_ASSET");

        require(specs[2] != uint256(0),               "L:ZERO_PID");
        require(specs[1].mod(specs[2]) == uint256(0), "L:INVALID_TERM_DAYS");
        require(specs[3] > uint256(0),                "L:ZERO_REQUEST_AMT");
    }

    /**
        @dev    Returns capital to Lenders, if the Borrower has not drawn down the Loan past the grace period.
        @param  liquidityAsset The IERC20 of the Liquidity Asset.
        @param  fundingLocker  The address of FundingLocker.
        @param  createdAt      The unix timestamp of Loan instantiation.
        @param  fundingPeriod  The duration of the funding period, after which funds can be reclaimed.
        @return excessReturned The amount of Liquidity Asset that was returned to the Loan from the FundingLocker.
     */
    function unwind(IERC20 liquidityAsset, address fundingLocker, uint256 createdAt, uint256 fundingPeriod) external returns (uint256 excessReturned) {
        // Only callable if Loan funding period has elapsed.
        require(block.timestamp > createdAt.add(fundingPeriod), "L:STILL_FUNDING_PERIOD");

        // Account for existing balance in Loan.
        uint256 preBal = liquidityAsset.balanceOf(address(this));

        // Drain funding from FundingLocker, transfers all the Liquidity Asset to this Loan.
        IFundingLocker(fundingLocker).drain();

        return liquidityAsset.balanceOf(address(this)).sub(preBal);
    }

    /**
        @dev    Liquidates a Borrower's collateral, via Uniswap, when a default is triggered. 
        @dev    Only the Loan can call this function. 
        @param  collateralAsset  The IERC20 of the Collateral Asset.
        @param  liquidityAsset   The address of Liquidity Asset.
        @param  superFactory     The factory that instantiated Loan.
        @param  collateralLocker The address of CollateralLocker.
        @return amountLiquidated The amount of Collateral Asset that was liquidated.
        @return amountRecovered  The amount of Liquidity Asset that was returned to the Loan from the liquidation.
     */
    function liquidateCollateral(
        IERC20  collateralAsset,
        address liquidityAsset,
        address superFactory,
        address collateralLocker
    )
        external
        returns (
            uint256 amountLiquidated,
            uint256 amountRecovered
        )
    {
        // Get the liquidation amount from CollateralLocker.
        uint256 liquidationAmt = collateralAsset.balanceOf(address(collateralLocker));

        // Pull the Collateral Asset from CollateralLocker.
        ICollateralLocker(collateralLocker).pull(address(this), liquidationAmt);

        if (address(collateralAsset) == liquidityAsset || liquidationAmt == uint256(0)) return (liquidationAmt, liquidationAmt);

        collateralAsset.safeApprove(UNISWAP_ROUTER, uint256(0));
        collateralAsset.safeApprove(UNISWAP_ROUTER, liquidationAmt);

        IMapleGlobals globals = _globals(superFactory);

        // Get minimum amount of loan asset get after swapping collateral asset.
        uint256 minAmount = Util.calcMinAmount(globals, address(collateralAsset), liquidityAsset, liquidationAmt);

        // Generate Uniswap path.
        address uniswapAssetForPath = globals.defaultUniswapPath(address(collateralAsset), liquidityAsset);
        bool middleAsset = uniswapAssetForPath != liquidityAsset && uniswapAssetForPath != address(0);

        address[] memory path = new address[](middleAsset ? 3 : 2);

        path[0] = address(collateralAsset);
        path[1] = middleAsset ? uniswapAssetForPath : liquidityAsset;

        if (middleAsset) path[2] = liquidityAsset;

        // Swap collateralAsset for Liquidity Asset.
        uint256[] memory returnAmounts = IUniswapRouter(UNISWAP_ROUTER).swapExactTokensForTokens(
            liquidationAmt,
            minAmount.sub(minAmount.mul(globals.maxSwapSlippage()).div(10_000)),
            path,
            address(this),
            block.timestamp
        );

        return(returnAmounts[0], returnAmounts[path.length - 1]);
    }

    /**********************************/
    /*** Governor Utility Functions ***/
    /**********************************/

    /**
        @dev   Transfers any locked funds to the Governor. 
        @dev   Only the Governor can call this function.
        @param token          The address of the token to be reclaimed.
        @param liquidityAsset The address of token that is used by the loan for drawdown and payments.
        @param globals        The instance of a MapleGlobals.
     */
    function reclaimERC20(address token, address liquidityAsset, IMapleGlobals globals) external {
        require(msg.sender == globals.governor(),               "L:NOT_GOV");
        require(token != liquidityAsset && token != address(0), "L:INVALID_TOKEN");
        IERC20(token).safeTransfer(msg.sender, IERC20(token).balanceOf(address(this)));
    }

    /************************/
    /*** Getter Functions ***/
    /************************/

    /**
        @dev    Returns if a default can be triggered.
        @param  nextPaymentDue     The unix timestamp of when payment is due.
        @param  defaultGracePeriod The amount of time after the next payment is due that a Borrower has before a liquidation can occur.
        @param  superFactory       The factory that instantiated Loan.
        @param  balance            The LoanFDT balance of account trying to trigger a default.
        @param  totalSupply        The total supply of LoanFDT.
        @return Whether a default can be triggered.
     */
    function canTriggerDefault(uint256 nextPaymentDue, uint256 defaultGracePeriod, address superFactory, uint256 balance, uint256 totalSupply) external view returns (bool) {
        bool pastDefaultGracePeriod = block.timestamp > nextPaymentDue.add(defaultGracePeriod);

        // Check if the Loan is past the default grace period and that the account triggering the default has a percentage of total LoanFDTs
        // that is greater than the minimum equity needed (specified in globals)
        return pastDefaultGracePeriod && balance >= ((totalSupply * _globals(superFactory).minLoanEquity()) / 10_000);
    }

    /**
        @dev    Returns information on next payment amount.
        @param  repaymentCalc   The address of RepaymentCalc.
        @param  nextPaymentDue  The unix timestamp of when payment is due.
        @param  lateFeeCalc     The address of LateFeeCalc.
        @return total           The entitled total amount needed to be paid in the next payment (Principal + Interest only when the next payment is last payment of the Loan).
        @return principal       The entitled principal amount needed to be paid in the next payment.
        @return interest        The entitled interest amount needed to be paid in the next payment.
        @return _nextPaymentDue The payment due date.
        @return paymentLate     Whether payment is late.
     */
    function getNextPayment(
        address repaymentCalc,
        uint256 nextPaymentDue,
        address lateFeeCalc
    )
        external
        view
        returns (
            uint256 total,
            uint256 principal,
            uint256 interest,
            uint256 _nextPaymentDue,
            bool    paymentLate
        )
    {
        _nextPaymentDue  = nextPaymentDue;

        // Get next payment amounts from RepaymentCalc.
        (total, principal, interest) = IRepaymentCalc(repaymentCalc).getNextPayment(address(this));

        paymentLate = block.timestamp > _nextPaymentDue;

        // If payment is late, add late fees.
        if (paymentLate) {
            uint256 lateFee = ILateFeeCalc(lateFeeCalc).getLateFee(interest);

            total    = total.add(lateFee);
            interest = interest.add(lateFee);
        }
    }

    /**
        @dev    Returns information on full payment amount.
        @param  repaymentCalc   The address of RepaymentCalc.
        @param  nextPaymentDue  The unix timestamp of when payment is due.
        @param  lateFeeCalc     The address of LateFeeCalc.
        @param  premiumCalc     The address of PremiumCalc.
        @return total           The Principal + Interest for the full payment.
        @return principal       The entitled principal amount needed to be paid in the full payment.
        @return interest        The entitled interest amount needed to be paid in the full payment.
     */
    function getFullPayment(
        address repaymentCalc,
        uint256 nextPaymentDue,
        address lateFeeCalc,
        address premiumCalc
    )
        external
        view
        returns (
            uint256 total,
            uint256 principal,
            uint256 interest
        )
    {
        (total, principal, interest) = IPremiumCalc(premiumCalc).getPremiumPayment(address(this));

        if (block.timestamp <= nextPaymentDue) return (total, principal, interest);

        // If payment is late, calculate and add late fees using interest amount from regular payment.
        (,, uint256 regInterest) = IRepaymentCalc(repaymentCalc).getNextPayment(address(this));

        uint256 lateFee = ILateFeeCalc(lateFeeCalc).getLateFee(regInterest);

        total    = total.add(lateFee);
        interest = interest.add(lateFee);
    }

    /**
        @dev    Calculates collateral required to drawdown amount.
        @param  collateralAsset The IERC20 of the Collateral Asset.
        @param  liquidityAsset  The IERC20 of the Liquidity Asset.
        @param  collateralRatio The percentage of drawdown value that must be posted as collateral.
        @param  superFactory    The factory that instantiated Loan.
        @param  amt             The drawdown amount.
        @return The amount of Collateral Asset required to post in CollateralLocker for given drawdown amount.
     */
    function collateralRequiredForDrawdown(
        IERC20Details collateralAsset,
        IERC20Details liquidityAsset,
        uint256 collateralRatio,
        address superFactory,
        uint256 amt
    )
        external
        view
        returns (uint256)
    {
        IMapleGlobals globals = _globals(superFactory);

        uint256 wad = _toWad(amt, liquidityAsset);  // Convert to WAD precision.

        // Fetch current value of Liquidity Asset and Collateral Asset (Chainlink oracles provide 8 decimal precision).
        uint256 liquidityAssetPrice  = globals.getLatestPrice(address(liquidityAsset));
        uint256 collateralPrice = globals.getLatestPrice(address(collateralAsset));

        // Calculate collateral required.
        uint256 collateralRequiredUSD = wad.mul(liquidityAssetPrice).mul(collateralRatio).div(10_000);  // 18 + 8 = 26 decimals
        uint256 collateralRequiredWAD = collateralRequiredUSD.div(collateralPrice);                     // 26 - 8 = 18 decimals

        return collateralRequiredWAD.mul(10 ** collateralAsset.decimals()).div(10 ** 18);  // 18 + collateralAssetDecimals - 18 = collateralAssetDecimals
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    function _globals(address loanFactory) internal view returns (IMapleGlobals) {
        return IMapleGlobals(ILoanFactory(loanFactory).globals());
    }

    function _toWad(uint256 amt, IERC20Details liquidityAsset) internal view returns (uint256) {
        return amt.mul(10 ** 18).div(10 ** liquidityAsset.decimals());
    }
}
