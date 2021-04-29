// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "../interfaces/ICollateralLocker.sol";
import "../interfaces/ICollateralLockerFactory.sol";
import "../interfaces/IERC20Details.sol";
import "../interfaces/IFundingLocker.sol";
import "../interfaces/IFundingLockerFactory.sol";
import "../interfaces/IMapleGlobals.sol";
import "../interfaces/ILateFeeCalc.sol";
import "../interfaces/ILoanFactory.sol";
import "../interfaces/IPremiumCalc.sol";
import "../interfaces/IRepaymentCalc.sol";
import "../interfaces/IUniswapRouter.sol";
import "../library/Util.sol";

import "lib/openzeppelin-contracts/contracts/token/ERC20/SafeERC20.sol";
import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";

/// @title LoanLib is a library of utility functions used by Loan.
library LoanLib {

    using SafeMath  for uint256;
    using SafeERC20 for IERC20;

    address public constant UNISWAP_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    /********************************/
    /*** Lender Utility Functions ***/
    /********************************/

    /**
        @dev    Perform sanity checks on the data passed in Loan constructor.
        @param  globals         MapleGlobals contract instance.
        @param  liquidityAsset  Contract address of the liquidity asset.
        @param  collateralAsset Contract address of the collateral asset.
        @param  specs           Contains specifications for this loan.
    */
    function loanSanityChecks(IMapleGlobals globals, address liquidityAsset, address collateralAsset, uint256[5] calldata specs) external view {
        require(globals.isValidLiquidityAsset(liquidityAsset),   "L:INVALID_LIQ_ASSET");
        require(globals.isValidCollateralAsset(collateralAsset), "L:INVALID_COL_ASSET");

        require(specs[2] != uint256(0),               "L:ZERO_PID");
        require(specs[1].mod(specs[2]) == uint256(0), "L:INVALID_TERM_DAYS");
        require(specs[3] > uint256(0),                "L:ZERO_REQUEST_AMT");
    }

    /**
        @dev    If the borrower has not drawn down loan past grace period, return capital to lenders.
        @param  liquidityAsset IERC20 of the liquidityAsset.
        @param  fundingLocker  Address of FundingLocker.
        @param  createdAt      Timestamp of Loan instantiation.
        @param  fundingPeriod  Duration of funding period, after which funds can be reclaimed.
        @return excessReturned Amount of liquidityAsset that was returned to the Loan from the FundingLocker.
    */
    function unwind(IERC20 liquidityAsset, address fundingLocker, uint256 createdAt, uint256 fundingPeriod) external returns (uint256 excessReturned) {
        // Only callable if time has passed drawdown grace period, set in MapleGlobals
        require(block.timestamp > createdAt.add(fundingPeriod), "L:STILL_FUNDING_PERIOD");

        uint256 preBal = liquidityAsset.balanceOf(address(this));  // Account for existing balance in Loan

        // Drain funding from FundingLocker, transfers all liquidityAsset to this Loan
        IFundingLocker(fundingLocker).drain();

        // Update excessReturned accounting for claim()
        return liquidityAsset.balanceOf(address(this)).sub(preBal);
    }

    /**
        @dev    Liquidate a Borrower's collateral via Uniswap when a default is triggered. Only the Loan can call this function.
        @param  collateralAsset  IERC20 of the collateralAsset.
        @param  liquidityAsset   Address of liquidityAsset.
        @param  superFactory     Factory that instantiated Loan.
        @param  collateralLocker Address of CollateralLocker.
        @return amountLiquidated Amount of collateralAsset that was liquidated.
        @return amountRecovered  Amount of liquidityAsset that was returned to the Loan from the liquidation.
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
        // Get liquidation amount from CollateralLocker
        uint256 liquidationAmt = collateralAsset.balanceOf(address(collateralLocker));
        
        // Pull collateralAsset from collateralLocker
        ICollateralLocker(collateralLocker).pull(address(this), liquidationAmt);

        if (address(collateralAsset) == liquidityAsset || liquidationAmt == uint256(0)) return (liquidationAmt, liquidationAmt);

        collateralAsset.safeApprove(UNISWAP_ROUTER, uint256(0));
        collateralAsset.safeApprove(UNISWAP_ROUTER, liquidationAmt);

        IMapleGlobals globals = _globals(superFactory);

        uint256 minAmount = Util.calcMinAmount(globals, address(collateralAsset), liquidityAsset, liquidationAmt);  // Minimum amount of loan asset get after swapping collateral asset

        // Generate path
        address uniswapAssetForPath = globals.defaultUniswapPath(address(collateralAsset), liquidityAsset);
        bool middleAsset = uniswapAssetForPath != liquidityAsset && uniswapAssetForPath != address(0);

        address[] memory path = new address[](middleAsset ? 3 : 2);

        path[0] = address(collateralAsset);
        path[1] = middleAsset ? uniswapAssetForPath : liquidityAsset;

        if (middleAsset) path[2] = liquidityAsset;

        // Swap collateralAsset for liquidityAsset
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
        @dev   Transfer any locked funds to the Governor. Only the Governor can call this function.
        @param token          Address of the token that need to reclaimed.
        @param liquidityAsset Address of loan asset that is supported by the loan in other words denominated currency in which it taking funds.
        @param globals        Instance of the `MapleGlobals` contract.
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
        @dev    Determines if a default can be triggered.
        @param  nextPaymentDue     Timestamp of when payment is due.
        @param  defaultGracePeriod Amount of time after `nextPaymentDue` that a borrower has before a liquidation can occur.
        @param  superFactory       Factory that instantiated Loan.
        @param  balance            LoanFDT balance of msg.sender.
        @param  totalSupply        LoanFDT totalSupply.
        @return boolean indicating if default can be triggered.
    */
    function canTriggerDefault(uint256 nextPaymentDue, uint256 defaultGracePeriod, address superFactory, uint256 balance, uint256 totalSupply) external view returns (bool) {
        bool pastDefaultGracePeriod = block.timestamp > nextPaymentDue.add(defaultGracePeriod);

        // Check if the loan is past the defaultGracePeriod and that `msg.sender` has a percentage of total LoanFDTs that is greater
        // than the minimum equity needed (specified in globals)
        return pastDefaultGracePeriod && balance >= ((totalSupply * _globals(superFactory).minLoanEquity()) / 10_000);
    }

    /**
        @dev    Returns information on next payment amount.
        @param  repaymentCalc   Address of RepaymentCalc.
        @param  nextPaymentDue  Timestamp of when payment is due.
        @param  lateFeeCalc     Address of LateFeeCalc.
        @return total           Entitled interest to the next payment, Principal + Interest only when the next payment is last payment of the loan.
        @return principal       Entitled principal amount needs to pay in the next payment.
        @return interest        Entitled interest amount needs to pay in the next payment.
        @return _nextPaymentDue Payment Due Date.
        @return paymentLate     Boolean if payment is late.
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

        // Get next payment amounts from repayment calc
        (total, principal, interest) = IRepaymentCalc(repaymentCalc).getNextPayment(address(this));

        paymentLate = block.timestamp > _nextPaymentDue;

        // If payment is late, add late fees
        if (paymentLate) {
            uint256 lateFee = ILateFeeCalc(lateFeeCalc).getLateFee(interest);
            
            total    = total.add(lateFee);
            interest = interest.add(lateFee);
        }
    }

    /**
        @dev    Returns information on full payment amount.
        @param  repaymentCalc   Address of RepaymentCalc.
        @param  nextPaymentDue  Timestamp of when payment is due.
        @param  lateFeeCalc     Address of LateFeeCalc.
        @param  premiumCalc     Address of PremiumCalc.
        @return total           Principal + Interest for the full payment.
        @return principal       Entitled principal amount needs to pay in the full payment.
        @return interest        Entitled interest amount needs to pay in the full payment.
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

        // If payment is late, calculate and add late fees using interest amount from regular payment
        (,, uint256 regInterest) = IRepaymentCalc(repaymentCalc).getNextPayment(address(this));

        uint256 lateFee = ILateFeeCalc(lateFeeCalc).getLateFee(regInterest);
        
        total    = total.add(lateFee);
        interest = interest.add(lateFee);
    }

    /**
        @dev    Helper for calculating collateral required to drawdown amt.
        @param  collateralAsset IERC20 of the collateralAsset.
        @param  liquidityAsset  IERC20 of the liquidityAsset.
        @param  collateralRatio Percentage of drawdown value that must be posted as collateral.
        @param  superFactory    Factory that instantiated Loan.
        @param  amt             Drawdown amount.
        @return Amount of collateralAsset required to post in CollateralLocker for given drawdown amt.
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

        uint256 wad = _toWad(amt, liquidityAsset);  // Convert to WAD precision

        // Fetch current value of liquidityAsset and collateralAsset (Chainlink oracles provide 8 decimal precision)
        uint256 liquidityAssetPrice  = globals.getLatestPrice(address(liquidityAsset));
        uint256 collateralPrice = globals.getLatestPrice(address(collateralAsset));

        // Calculate collateral required
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
