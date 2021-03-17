// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

import "../interfaces/ICollateralLocker.sol";
import "../interfaces/ICollateralLockerFactory.sol";
import "../interfaces/IERC20Details.sol";
import "../interfaces/IFundingLocker.sol";
import "../interfaces/IFundingLockerFactory.sol";
import "../interfaces/IGlobals.sol";
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

    enum State { Live, Active, Matured, Expired, Liquidated }

    address public constant UNISWAP_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    /**
        @dev If the borrower has not drawn down loan past grace period, return capital to lenders.
        @param loanAsset       IERC20 of the loanAsset
        @param superFactory    Factory that instantiated Loan
        @param fundingLocker   Address of FundingLocker
        @param createdAt       Timestamp of Loan instantiation
        @return excessReturned Amount of loanAsset that was returned to the Loan from the FundingLocker
    */
    function unwind(IERC20 loanAsset, address superFactory, address fundingLocker, uint256 createdAt) external returns(uint256 excessReturned) {
        IGlobals globals = _globals(superFactory);

        // Only callable if time has passed drawdown grace period, set in MapleGlobals
        require(block.timestamp > createdAt.add(globals.drawdownGracePeriod()));

        uint256 preBal = loanAsset.balanceOf(address(this));  // Account for existing balance in Loan

        // Drain funding from FundingLocker, transfers all loanAsset to this Loan
        IFundingLocker(fundingLocker).drain();

        // Update excessReturned accounting for claim()
        return loanAsset.balanceOf(address(this)).sub(preBal);
    }

    /**
        @dev Triggers default flow for loan, liquidating all collateral and updating accounting.
        @param collateralAsset   IERC20 of the collateralAsset
        @param loanAsset         Address of loanAsset
        @param superFactory      Factory that instantiated Loan
        @param collateralLocker  Address of CollateralLocker
        @return amountLiquidated Amount of collateralAsset that was liquidated
        @return amountRecovered  Amount of loanAsset that was returned to the Loan from the liquidation
    */
    function triggerDefault(
        IERC20 collateralAsset,
        address loanAsset,
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

        if (address(collateralAsset) != loanAsset && liquidationAmt > 0) {
            collateralAsset.safeIncreaseAllowance(UNISWAP_ROUTER, liquidationAmt);

            IGlobals globals = _globals(superFactory);

            uint256 minAmount = Util.calcMinAmount(globals, address(collateralAsset), loanAsset, liquidationAmt);  // Minimum amount of loan asset get after swapping collateral asset

            // Generate path
            address uniswapAssetForPath = globals.defaultUniswapPath(address(collateralAsset), loanAsset);
            bool middleAsset = uniswapAssetForPath != loanAsset && uniswapAssetForPath != address(0);

            address[] memory path = new address[](middleAsset ? 3 : 2);

            path[0] = address(collateralAsset);
            path[1] = middleAsset ? uniswapAssetForPath : loanAsset;

            if(middleAsset) path[2] = loanAsset;

            // Swap collateralAsset for loanAsset
            uint256[] memory returnAmounts = IUniswapRouter(UNISWAP_ROUTER).swapExactTokensForTokens(
                liquidationAmt,
                minAmount.sub(minAmount.mul(globals.maxSwapSlippage()).div(10000)),
                path,
                address(this),
                block.timestamp
            );

            amountLiquidated = returnAmounts[0];
            amountRecovered  = returnAmounts[path.length - 1];
        } else {
            amountLiquidated = liquidationAmt;
            amountRecovered  = liquidationAmt;
        }
    }

    /**
        @dev Determines if a default can be triggered.
        @param nextPaymentDue Timestamp of when payment is due
        @param superFactory   Factory that instantiated Loan
        @param balance        LoanFDT balance of msg.sender
        @param totalSupply    LoanFDT totalSupply
        @return boolean indicating if default can be triggered
    */
    function canTriggerDefault(uint256 nextPaymentDue, address superFactory, uint256 balance, uint256 totalSupply) external returns(bool) {

        bool pastGracePeriod = block.timestamp > nextPaymentDue.add(_globals(superFactory).gracePeriod());

        // Check if the loan is past the gracePeriod and that msg.sender has a percentage of total LoanFDTs that is greater
        // the minimum equity needed (specified in globals)
        return pastGracePeriod && balance >= totalSupply * _globals(superFactory).minLoanEquity() / 10_000;
    }

    /**
        @dev Returns information on next payment amount.
        @param superFactory    Factory that instantiated Loan
        @param repaymentCalc   Address of RepaymentCalc
        @param _nextPaymentDue Timestamp of when payment is due
        @param lateFeeCalc     Address of LateFeeCalc
        @return total          Principal + Interest
        @return principal      Principal 
        @return interest       Interest
        @return nextPaymentDue Payment Due Date
    */
    function getNextPayment(
        address superFactory,
        address repaymentCalc,
        uint256 _nextPaymentDue,
        address lateFeeCalc
    ) 
        public
        view
        returns (
            uint256 total,
            uint256 principal,
            uint256 interest,
            uint256 nextPaymentDue,
            bool    paymentLate
        ) 
    {
        IGlobals globals = _globals(superFactory);
        nextPaymentDue   = _nextPaymentDue;

        // Get next payment amounts from repayment calc
        (total, principal, interest) = IRepaymentCalc(repaymentCalc).getNextPayment(address(this));

        paymentLate = block.timestamp > nextPaymentDue;

        // If payment is late, add late fees
        if (paymentLate) {
            (uint256 totalExtra, uint256 principalExtra, uint256 interestExtra) = ILateFeeCalc(lateFeeCalc).getLateFee(address(this));

            total     = total.add(totalExtra);
            interest  = interest.add(interestExtra);
            principal = principal.add(principalExtra);
        }
    }

    /**
        @dev Helper for calculating collateral required to drawdown amt.
        @param collateralAsset IERC20 of the collateralAsset
        @param loanAsset       IERC20 of the loanAsset
        @param collateralRatio Percentage of drawdown value that must be posted as collateral
        @param superFactory    Factory that instantiated Loan
        @param amt             Drawdown amount
        @return collateralRequiredFIN The amount of collateralAsset required to post in CollateralLocker for given drawdown amt
    */
    function collateralRequiredForDrawdown(
        IERC20Details collateralAsset,
        IERC20Details loanAsset,
        uint256 collateralRatio,
        address superFactory,
        uint256 amt
    ) 
        external
        view
        returns (uint256 collateralRequiredFIN) 
    {
        IGlobals globals = _globals(superFactory);

        uint256 wad = _toWad(amt, loanAsset);  // Convert to WAD precision

        // Fetch value of collateral and funding asset
        uint256 loanAssetPrice  = globals.getLatestPrice(address(loanAsset));
        uint256 collateralPrice = globals.getLatestPrice(address(collateralAsset));

        // Calculate collateral required
        uint256 collateralRequiredUSD = loanAssetPrice.mul(wad).mul(collateralRatio).div(10000);
        uint256 collateralRequiredWEI = collateralRequiredUSD.div(collateralPrice);
        collateralRequiredFIN = collateralRequiredWEI.div(10 ** (18 - collateralAsset.decimals()));
    }

    /**
        @dev Transfer any locked funds to the governor.
        @param token Address of the token that need to reclaimed.
        @param loanAsset Address of loan asset that is supported by the loan in other words denominated currency in which it taking funds.
        @param collateralAsset Address of the collateral asset supported by the loan.
        @param globals Instance of the `MapleGlobals` contract.
     */
    function reclaimERC20(address token, address loanAsset, address collateralAsset, IGlobals globals) external {
        require(msg.sender == globals.governor(), "Loan:NOT_AUTHORISED");
        require(token != loanAsset && token != address(0) && token != collateralAsset, "Loan:INVALID_TOKEN");
        IERC20(token).safeTransfer(msg.sender, IERC20(token).balanceOf(address(this)));
    }

    function _globals(address loanFactory) internal view returns (IGlobals) {
        return IGlobals(ILoanFactory(loanFactory).globals());
    }

    function _toWad(uint256 amt, IERC20Details loanAsset) internal view returns(uint256) {
        return amt.mul(10 ** 18).div(10 ** loanAsset.decimals());
    }
}
