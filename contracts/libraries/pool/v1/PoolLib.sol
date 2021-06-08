// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "../../../../lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/SafeERC20.sol";

import "../../../external-interfaces/IBPool.sol";
import "../../../external-interfaces/IERC20Details.sol";

import "../../../core/debt-locker/v1/interfaces/IDebtLockerFactory.sol";
import "../../../core/globals/v1/interfaces/IMapleGlobals.sol";
import "../../../core/loan/v1/interfaces/ILoan.sol";
import "../../../core/loan/v1/interfaces/ILoanFactory.sol";
import "../../../core/liquidity-locker/v1/interfaces/ILiquidityLocker.sol";
import "../../../core/stake-locker/v1/interfaces/IStakeLocker.sol";

/// @title PoolLib is a library of utility functions used by Pool.
library PoolLib {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant MAX_UINT256 = uint256(-1);
    uint256 public constant WAD         = 10 ** 18;
    uint8   public constant DL_FACTORY  = 1;         // Factory type of DebtLockerFactory

    event         LoanFunded(address indexed loan, address debtLocker, uint256 amountFunded);
    event DepositDateUpdated(address indexed liquidityProvider, uint256 depositDate);

    /***************************************/
    /*** Pool Delegate Utility Functions ***/
    /***************************************/

    /**
        @dev   Conducts sanity checks for Pools in the constructor.
        @param globals        Instance of a MapleGlobals.
        @param liquidityAsset Asset used by Pool for liquidity to fund loans.
        @param stakeAsset     Asset escrowed in StakeLocker.
        @param stakingFee     Fee that the Stakers earn on interest, in basis points.
        @param delegateFee    Fee that the Pool Delegate earns on interest, in basis points.
    */
    function poolSanityChecks(
        IMapleGlobals globals,
        address liquidityAsset,
        address stakeAsset,
        uint256 stakingFee,
        uint256 delegateFee
    ) external view {
        IBPool bPool = IBPool(stakeAsset);

        require(globals.isValidLiquidityAsset(liquidityAsset), "P:INVALID_LIQ_ASSET");
        require(stakingFee.add(delegateFee) <= 10_000,         "P:INVALID_FEES");
        require(
            globals.isValidBalancerPool(address(stakeAsset)) &&
            bPool.isBound(globals.mpl())                     &&
            bPool.isBound(liquidityAsset)                    &&
            bPool.isFinalized(),
            "P:INVALID_BALANCER_POOL"
        );
    }

    /**
        @dev   Funds a Loan for an amount, utilizing the supplied DebtLockerFactory for DebtLockers.
        @dev   It emits a `LoanFunded` event.
        @param debtLockers     Mapping contains the DebtLocker contract address corresponding to the DebtLockerFactory and Loan.
        @param superFactory    Address of the PoolFactory.
        @param liquidityLocker Address of the LiquidityLocker contract attached with this Pool.
        @param loan            Address of the Loan to fund.
        @param dlFactory       The DebtLockerFactory to utilize.
        @param amt             Amount to fund the Loan.
    */
    function fundLoan(
        mapping(address => mapping(address => address)) storage debtLockers,
        address superFactory,
        address liquidityLocker,
        address loan,
        address dlFactory,
        uint256 amt
    ) external {
        IMapleGlobals globals = IMapleGlobals(ILoanFactory(superFactory).globals());
        address loanFactory   = ILoan(loan).superFactory();

        // Auth checks.
        require(globals.isValidLoanFactory(loanFactory),                        "P:INVALID_LF");
        require(ILoanFactory(loanFactory).isLoan(loan),                         "P:INVALID_L");
        require(globals.isValidSubFactory(superFactory, dlFactory, DL_FACTORY), "P:INVALID_DLF");

        address debtLocker = debtLockers[loan][dlFactory];

        // Instantiate DebtLocker if it doesn't exist withing this factory
        if (debtLocker == address(0)) {
            debtLocker = IDebtLockerFactory(dlFactory).newLocker(loan);
            debtLockers[loan][dlFactory] = debtLocker;
        }

        // Fund the Loan.
        ILiquidityLocker(liquidityLocker).fundLoan(loan, debtLocker, amt);

        emit LoanFunded(loan, debtLocker, amt);
    }

    /**
        @dev    Helper function used by Pool `claim` function, for when if a default has occurred.
        @param  liquidityAsset                  IERC20 of Liquidity Asset.
        @param  stakeLocker                     Address of StakeLocker.
        @param  stakeAsset                      Address of BPTs.
        @param  defaultSuffered                 Amount of shortfall in defaulted Loan after liquidation.
        @return bptsBurned                      Amount of BPTs burned to cover shortfall.
        @return postBurnBptBal                  Amount of BPTs returned to StakeLocker after burn.
        @return liquidityAssetRecoveredFromBurn Amount of Liquidity Asset recovered from burn.
    */
    function handleDefault(
        IERC20  liquidityAsset,
        address stakeLocker,
        address stakeAsset,
        uint256 defaultSuffered
    )
        external
        returns (
            uint256 bptsBurned,
            uint256 postBurnBptBal,
            uint256 liquidityAssetRecoveredFromBurn
        )
    {

        IBPool bPool = IBPool(stakeAsset);  // stakeAsset = Balancer Pool Tokens

        // Check amount of Liquidity Asset coverage that exists in the StakeLocker.
        uint256 availableSwapOut = getSwapOutValueLocker(stakeAsset, address(liquidityAsset), stakeLocker);

        // Pull BPTs from StakeLocker.
        IStakeLocker(stakeLocker).pull(address(this), bPool.balanceOf(stakeLocker));

        // To maintain accounting, account for direct transfers into Pool.
        uint256 preBurnLiquidityAssetBal = liquidityAsset.balanceOf(address(this));
        uint256 preBurnBptBal            = bPool.balanceOf(address(this));

        // Burn enough BPTs for Liquidity Asset to cover default suffered.
        bPool.exitswapExternAmountOut(
            address(liquidityAsset),
            availableSwapOut >= defaultSuffered ? defaultSuffered : availableSwapOut,  // Burn BPTs up to defaultSuffered amount
            preBurnBptBal
        );

        // Return remaining BPTs to StakeLocker.
        postBurnBptBal = bPool.balanceOf(address(this));
        bptsBurned     = preBurnBptBal.sub(postBurnBptBal);
        bPool.transfer(stakeLocker, postBurnBptBal);
        liquidityAssetRecoveredFromBurn = liquidityAsset.balanceOf(address(this)).sub(preBurnLiquidityAssetBal);
        IStakeLocker(stakeLocker).updateLosses(bptsBurned);  // Update StakeLockerFDT loss accounting for BPTs
    }

    /**
        @dev    Calculates portions of claim from DebtLocker to be used by Pool `claim` function.
        @param  claimInfo           [0] = Total Claimed
                                    [1] = Interest Claimed
                                    [2] = Principal Claimed
                                    [3] = Fee Claimed
                                    [4] = Excess Returned Claimed
                                    [5] = Amount Recovered (from Liquidation)
                                    [6] = Default Suffered
        @param  delegateFee         Portion of interest (basis points) that goes to the Pool Delegate.
        @param  stakingFee          Portion of interest (basis points) that goes to the StakeLocker.
        @return poolDelegatePortion Total funds to send to the Pool Delegate.
        @return stakeLockerPortion  Total funds to send to the StakeLocker.
        @return principalClaim      Total principal claim.
        @return interestClaim       Total interest claim.
    */
    function calculateClaimAndPortions(
        uint256[7] calldata claimInfo,
        uint256 delegateFee,
        uint256 stakingFee
    )
        external
        pure
        returns (
            uint256 poolDelegatePortion,
            uint256 stakeLockerPortion,
            uint256 principalClaim,
            uint256 interestClaim
        )
    {
        poolDelegatePortion = claimInfo[1].mul(delegateFee).div(10_000).add(claimInfo[3]);  // Pool Delegate portion of interest plus fee.
        stakeLockerPortion  = claimInfo[1].mul(stakingFee).div(10_000);                     // StakeLocker portion of interest.

        principalClaim = claimInfo[2].add(claimInfo[4]).add(claimInfo[5]);                                     // principal + excess + amountRecovered
        interestClaim  = claimInfo[1].sub(claimInfo[1].mul(delegateFee).div(10_000)).sub(stakeLockerPortion);  // leftover interest
    }

    /**
        @dev   Checks that the deactivation is allowed.
        @param globals        Instance of a MapleGlobals.
        @param principalOut   Amount of funds that are already funded to Loans.
        @param liquidityAsset Liquidity Asset of the Pool.
    */
    function validateDeactivation(IMapleGlobals globals, uint256 principalOut, address liquidityAsset) external view {
        require(principalOut <= _convertFromUsd(globals, liquidityAsset, 100), "P:PRINCIPAL_OUTSTANDING");
    }

    /********************************************/
    /*** Liquidity Provider Utility Functions ***/
    /********************************************/

    /**
        @dev   Updates the effective deposit date based on how much new capital has been added.
               If more capital is added, the deposit date moves closer to the current timestamp.
        @dev   It emits a `DepositDateUpdated` event.
        @param amt     Total deposit amount.
        @param account Address of account depositing.
    */
    function updateDepositDate(mapping(address => uint256) storage depositDate, uint256 balance, uint256 amt, address account) internal {
        uint256 prevDate = depositDate[account];

        // prevDate + (now - prevDate) * (amt / (balance + amt))
        // NOTE: prevDate = 0 implies balance = 0, and equation reduces to now
        uint256 newDate = (balance + amt) > 0
            ? prevDate.add(block.timestamp.sub(prevDate).mul(amt).div(balance + amt))
            : prevDate;

        depositDate[account] = newDate;
        emit DepositDateUpdated(account, newDate);
    }

    /**
        @dev Performs all necessary checks for a `transferByCustodian` call.
        @dev From and to must always be equal.
    */
    function transferByCustodianChecks(address from, address to, uint256 amount) external pure {
        require(to == from,                 "P:INVALID_RECEIVER");
        require(amount != uint256(0),       "P:INVALID_AMT");
    }

    /**
        @dev Performs all necessary checks for an `increaseCustodyAllowance` call.
    */
    function increaseCustodyAllowanceChecks(address custodian, uint256 amount, uint256 newTotalAllowance, uint256 fdtBal) external pure {
        require(custodian != address(0),     "P:INVALID_CUSTODIAN");
        require(amount    != uint256(0),     "P:INVALID_AMT");
        require(newTotalAllowance <= fdtBal, "P:INSUF_BALANCE");
    }

    /**********************************/
    /*** Governor Utility Functions ***/
    /**********************************/

    /**
        @dev   Transfers any locked funds to the Governor. Only the Governor can call this function.
        @param token          Address of the token to be reclaimed.
        @param liquidityAsset Address of Liquidity Asset that is supported by the Pool.
        @param globals        Instance of a MapleGlobals.
    */
    function reclaimERC20(address token, address liquidityAsset, IMapleGlobals globals) external {
        require(msg.sender == globals.governor(), "P:NOT_GOV");
        require(token != liquidityAsset && token != address(0), "P:INVALID_TOKEN");
        IERC20(token).safeTransfer(msg.sender, IERC20(token).balanceOf(address(this)));
    }

    /************************/
    /*** Getter Functions ***/
    /************************/

    /**
        @dev Official Balancer pool bdiv() function. Does synthetic float with 10^-18 precision.
    */
    function _bdiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "P:DIV_ZERO");
        uint256 c0 = a * WAD;
        require(a == 0 || c0 / a == WAD, "P:DIV_INTERNAL");  // bmul overflow
        uint256 c1 = c0 + (b / 2);
        require(c1 >= c0, "P:DIV_INTERNAL");  //  badd require
        return c1 / b;
    }

    /**
        @dev    Calculates the value of BPT in units of Liquidity Asset.
        @dev    Vulnerable to flash-loan attacks where the attacker can artificially inflate the BPT price by swapping a large amount
                of Liquidity Asset into the Pool and swapping back after this function is called.
        @param  _bPool         Address of Balancer pool.
        @param  liquidityAsset Asset used by Pool for liquidity to fund Loans.
        @param  staker         Address that deposited BPTs to StakeLocker.
        @param  stakeLocker    Escrows BPTs deposited by Staker.
        @return USDC value of Staker BPTs.
    */
    function BPTVal(
        address _bPool,
        address liquidityAsset,
        address staker,
        address stakeLocker
    ) external view returns (uint256) {
        IBPool bPool = IBPool(_bPool);

        // StakeLockerFDTs are minted 1:1 (in wei) in the StakeLocker when staking BPTs, thus representing stake amount.
        // These are burned when withdrawing staked BPTs, thus representing the current stake amount.
        uint256 amountStakedBPT       = IERC20(stakeLocker).balanceOf(staker);
        uint256 totalSupplyBPT        = IERC20(_bPool).totalSupply();
        uint256 liquidityAssetBalance = bPool.getBalance(liquidityAsset);
        uint256 liquidityAssetWeight  = bPool.getNormalizedWeight(liquidityAsset);

        // liquidityAsset value = (amountStaked/totalSupply) * (liquidityAssetBalance/liquidityAssetWeight)
        return _bdiv(amountStakedBPT, totalSupplyBPT).mul(_bdiv(liquidityAssetBalance, liquidityAssetWeight)).div(WAD);
    }

    /**
        @dev    Calculates Liquidity Asset swap out value of staker BPT balance escrowed in StakeLocker.
        @param  _bPool         Balancer pool that issues the BPTs.
        @param  liquidityAsset Swap out asset (e.g. USDC) to receive when burning BPTs.
        @param  staker         Address that deposited BPTs to StakeLocker.
        @param  stakeLocker    Escrows BPTs deposited by Staker.
        @return liquidityAsset Swap out value of staker BPTs.
    */
    function getSwapOutValue(
        address _bPool,
        address liquidityAsset,
        address staker,
        address stakeLocker
    ) public view returns (uint256) {
        return _getSwapOutValue(_bPool, liquidityAsset, IERC20(stakeLocker).balanceOf(staker));
    }

    /**
        @dev    Calculates Liquidity Asset swap out value of entire BPT balance escrowed in StakeLocker.
        @param  _bPool         Balancer pool that issues the BPTs.
        @param  liquidityAsset Swap out asset (e.g. USDC) to receive when burning BPTs.
        @param  stakeLocker    Escrows BPTs deposited by Staker.
        @return liquidityAsset Swap out value of StakeLocker BPTs.
    */
    function getSwapOutValueLocker(
        address _bPool,
        address liquidityAsset,
        address stakeLocker
    ) public view returns (uint256) {
        return _getSwapOutValue(_bPool, liquidityAsset, IBPool(_bPool).balanceOf(stakeLocker));
    }

    function _getSwapOutValue(
        address _bPool,
        address liquidityAsset,
        uint256 poolAmountIn
    ) internal view returns (uint256) {
        // Fetch Balancer pool token information
        IBPool bPool            = IBPool(_bPool);
        uint256 tokenBalanceOut = bPool.getBalance(liquidityAsset);
        uint256 tokenWeightOut  = bPool.getDenormalizedWeight(liquidityAsset);
        uint256 poolSupply      = bPool.totalSupply();
        uint256 totalWeight     = bPool.getTotalDenormalizedWeight();
        uint256 swapFee         = bPool.getSwapFee();

        // Returns the amount of liquidityAsset that can be recovered from BPT burning
        uint256 tokenAmountOut = bPool.calcSingleOutGivenPoolIn(
            tokenBalanceOut,
            tokenWeightOut,
            poolSupply,
            totalWeight,
            poolAmountIn,
            swapFee
        );

        // Max amount that can be swapped based on amount of liquidityAsset in the Balancer Pool
        uint256 maxSwapOut = tokenBalanceOut.mul(bPool.MAX_OUT_RATIO()).div(WAD);

        return tokenAmountOut <= maxSwapOut ? tokenAmountOut : maxSwapOut;
    }

    /**
        @dev    Calculates BPTs required if burning BPTs for liquidityAsset, given supplied tokenAmountOutRequired.
        @dev    Vulnerable to flash-loan attacks where the attacker can artificially inflate the BPT price by swapping a large amount
                of liquidityAsset into the pool and swapping back after this function is called.
        @param  _bPool                       Balancer pool that issues the BPTs.
        @param  liquidityAsset               Swap out asset (e.g. USDC) to receive when burning BPTs.
        @param  staker                       Address that deposited BPTs to stakeLocker.
        @param  stakeLocker                  Escrows BPTs deposited by staker.
        @param  liquidityAssetAmountRequired Amount of liquidityAsset required to recover.
        @return poolAmountInRequired         poolAmountIn required.
        @return stakerBalance                poolAmountIn currently staked.
    */
    function getPoolSharesRequired(
        address _bPool,
        address liquidityAsset,
        address staker,
        address stakeLocker,
        uint256 liquidityAssetAmountRequired
    ) public view returns (uint256 poolAmountInRequired, uint256 stakerBalance) {
        // Fetch Balancer pool token information.
        IBPool bPool = IBPool(_bPool);

        uint256 tokenBalanceOut = bPool.getBalance(liquidityAsset);
        uint256 tokenWeightOut  = bPool.getDenormalizedWeight(liquidityAsset);
        uint256 poolSupply      = bPool.totalSupply();
        uint256 totalWeight     = bPool.getTotalDenormalizedWeight();
        uint256 swapFee         = bPool.getSwapFee();

        // Fetch amount of BPTs required to burn to receive Liquidity Asset amount required.
        poolAmountInRequired = bPool.calcPoolInGivenSingleOut(
            tokenBalanceOut,
            tokenWeightOut,
            poolSupply,
            totalWeight,
            liquidityAssetAmountRequired,
            swapFee
        );

        // Fetch amount staked in StakeLocker by Staker.
        stakerBalance = IERC20(stakeLocker).balanceOf(staker);
    }

    /**
        @dev    Returns information on the stake requirements.
        @param  globals                    Instance of a MapleGlobals.
        @param  balancerPool               Address of Balancer pool.
        @param  liquidityAsset             Address of Liquidity Asset, to be returned from swap out.
        @param  poolDelegate               Address of Pool Delegate.
        @param  stakeLocker                Address of StakeLocker.
        @return swapOutAmountRequired      Min amount of Liquidity Asset coverage from staking required (in Liquidity Asset units).
        @return currentPoolDelegateCover   Present amount of Liquidity Asset coverage from Pool Delegate stake (in Liquidity Asset units).
        @return enoughStakeForFinalization If enough stake is present from Pool Delegate for Pool finalization.
        @return poolAmountInRequired       BPTs required for minimum Liquidity Asset coverage.
        @return poolAmountPresent          Current staked BPTs.
    */
    function getInitialStakeRequirements(IMapleGlobals globals, address balancerPool, address liquidityAsset, address poolDelegate, address stakeLocker) external view returns (
        uint256 swapOutAmountRequired,
        uint256 currentPoolDelegateCover,
        bool    enoughStakeForFinalization,
        uint256 poolAmountInRequired,
        uint256 poolAmountPresent
    ) {
        swapOutAmountRequired = _convertFromUsd(globals, liquidityAsset, globals.swapOutRequired());
        (
            poolAmountInRequired,
            poolAmountPresent
        ) = getPoolSharesRequired(balancerPool, liquidityAsset, poolDelegate, stakeLocker, swapOutAmountRequired);

        currentPoolDelegateCover   = getSwapOutValue(balancerPool, liquidityAsset, poolDelegate, stakeLocker);
        enoughStakeForFinalization = poolAmountPresent >= poolAmountInRequired;
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    /**
        @dev   Converts from WAD precision to Liquidity Asset precision.
        @param amt                    Amount to convert.
        @param liquidityAssetDecimals Liquidity Asset decimal.
    */
    function fromWad(uint256 amt, uint256 liquidityAssetDecimals) external pure returns (uint256) {
        return amt.mul(10 ** liquidityAssetDecimals).div(WAD);
    }

    /**
        @dev    Returns Liquidity Asset in Liquidity Asset units when given integer USD (E.g., $100 = 100).
        @param  globals        Instance of a MapleGlobals.
        @param  liquidityAsset Liquidity Asset of the pool.
        @param  usdAmount      USD amount to convert, in integer units (e.g., $100 = 100).
        @return usdAmount worth of Liquidity Asset, in Liquidity Asset units.
    */
    function _convertFromUsd(IMapleGlobals globals, address liquidityAsset, uint256 usdAmount) internal view returns (uint256) {
        return usdAmount
            .mul(10 ** 8)                                         // Cancel out 10 ** 8 decimals from oracle.
            .mul(10 ** IERC20Details(liquidityAsset).decimals())  // Convert to Liquidity Asset precision.
            .div(globals.getLatestPrice(liquidityAsset));         // Convert to Liquidity Asset value.
    }
}
