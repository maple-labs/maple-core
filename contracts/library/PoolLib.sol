// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/SafeERC20.sol";
import "../interfaces/ILoan.sol";
import "../interfaces/IBPool.sol";
import "../interfaces/IGlobals.sol";
import "../interfaces/ILiquidityLocker.sol";
import "../interfaces/IERC20Details.sol";
import "../interfaces/ILoanFactory.sol";
import "../interfaces/IStakeLocker.sol";
import "../interfaces/IDebtLockerFactory.sol";

/// @title PoolLib is a library of utility functions used by Pool.
library PoolLib {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant MAX_UINT256 = uint256(-1);
    uint256 public constant WAD         = 10 ** 18;
    uint8   public constant DL_FACTORY  = 1;         // Factory type of `DebtLockerFactory`

    event         LoanFunded(address indexed loan, address debtLocker, uint256 amountFunded);
    event DepositDateUpdated(address indexed lp, uint256 depositDate);
    event           Cooldown(address indexed lp);

    /***************************************/
    /*** Pool Delegate Utility Functions ***/
    /***************************************/

    /** 
        @dev Conducts sanity checks for Pools in the constructor
        @param globals        Address of MapleGlobals
        @param liquidityAsset Asset used by Pool for liquidity to fund loans
        @param stakeAsset     Asset escrowed in StakeLocker
        @param stakingFee     Fee that `stakers` earn on interest, in basis points
        @param delegateFee    Fee that `_poolDelegate` earns on interest, in basis points
    */
    function poolSanityChecks(
        IGlobals globals, 
        address liquidityAsset, 
        address stakeAsset, 
        uint256 stakingFee, 
        uint256 delegateFee
    ) external {
        require(globals.isValidLoanAsset(liquidityAsset),  "Pool:INVALID_LIQ_ASSET");
        require(stakingFee.add(delegateFee) <= 10_000,     "Pool:INVALID_FEES");
        require(
            IBPool(stakeAsset).isBound(globals.mpl())  && 
            IBPool(stakeAsset).isBound(liquidityAsset) &&
            IBPool(stakeAsset).isFinalized(), 
            "Pool:INVALID_BALANCER_POOL"
        );
    }

    /**
        @dev Fund a loan for amt, utilize the supplied debtLockerFactory for debt lockers.
        @param  debtLockers     Mapping contains the `debtLocker` contract address corresponds to the `dlFactory` and `loan`.
        @param  superFactory    Address of the `PoolFactory`
        @param  liquidityLocker Address of the `liquidityLocker` contract attached with this Pool
        @param  loan            Address of the loan to fund
        @param  dlFactory       The debt locker factory to utilize
        @param  amt             Amount to fund the loan
    */
    function fundLoan(
        mapping(address => mapping(address => address)) storage debtLockers,
        address superFactory,
        address liquidityLocker,
        address loan,
        address dlFactory,
        uint256 amt
    ) external {
        IGlobals globals    = _globals(superFactory);
        address loanFactory = ILoan(loan).superFactory();

        // Auth checks
        require(globals.isValidLoanFactory(loanFactory),                        "Pool:INVALID_LOAN_FACTORY");
        require(ILoanFactory(loanFactory).isLoan(loan),                         "Pool:INVALID_LOAN");
        require(globals.isValidSubFactory(superFactory, dlFactory, DL_FACTORY), "Pool:INVALID_DL_FACTORY");

        address _debtLocker = debtLockers[loan][dlFactory];

        // Instantiate locker if it doesn't exist with this factory type
        if (_debtLocker == address(0)) {
            address debtLocker = IDebtLockerFactory(dlFactory).newLocker(loan);
            debtLockers[loan][dlFactory] = debtLocker;
            _debtLocker = debtLocker;
        }
    
        // Fund loan
        ILiquidityLocker(liquidityLocker).fundLoan(loan, _debtLocker, amt);
        
        emit LoanFunded(loan, _debtLocker, amt);
    }

    /**
        @dev Helper function for claim() if a default has occurred.
        @param  liquidityAsset  IERC20 of liquidityAsset
        @param  stakeLocker     Address of stakeLocker
        @param  stakeAsset      Address of BPTs
        @param  loan            Address of loan
        @param  defaultSuffered Amount of shortfall in defaulted loan after liquidation
        @return bptsBurned                      Amount of BPTs burned to cover shortfall
        @return postBurnBptBal                  Amount of BPTs returned to stakeLocker after burn
        @return liquidityAssetRecoveredFromBurn Amount of liquidityAsset recovered from burn
     */
    function handleDefault(
        IERC20  liquidityAsset,
        address stakeLocker,
        address stakeAsset,
        address loan,
        uint256 defaultSuffered
    ) 
        external
        returns (
            uint256 bptsBurned,
            uint256 postBurnBptBal,
            uint256 liquidityAssetRecoveredFromBurn
        ) 
    {

        IBPool bPool = IBPool(stakeAsset);  // stakeAsset == Balancer Pool Tokens

        // Check amount of liquidityAsset coverage that exists in the StakeLocker
        uint256 availableSwapOut = getSwapOutValueLocker(stakeAsset, address(liquidityAsset), stakeLocker);

        // Pull BPTs from StakeLocker
        require(IStakeLocker(stakeLocker).pull(address(this), bPool.balanceOf(stakeLocker)), "Pool:STAKE_PULL");

        // To maintain accounting, account for direct transfers into Pool
        uint256 preBurnLiquidityAssetBal = liquidityAsset.balanceOf(address(this));
        uint256 preBurnBptBal            = bPool.balanceOf(address(this));

        // Burn enough BPTs for liquidityAsset to cover defaultSuffered
        bPool.exitswapExternAmountOut(
            address(liquidityAsset), 
            availableSwapOut >= defaultSuffered ? defaultSuffered : availableSwapOut,  // Burn BPTs up to defaultSuffered amount
            preBurnBptBal
        );

        // Return remaining BPTs to stakeLocker
        postBurnBptBal = bPool.balanceOf(address(this));
        bptsBurned     = preBurnBptBal.sub(postBurnBptBal);
        bPool.transfer(stakeLocker, postBurnBptBal);
        liquidityAssetRecoveredFromBurn = liquidityAsset.balanceOf(address(this)).sub(preBurnLiquidityAssetBal);
        IStakeLocker(stakeLocker).updateLosses(bptsBurned);  // Update StakeLocker FDT loss accounting for BPTs
    }

    /**
        @dev Calculate portions of claim from DebtLocker to be used by Pool claim function.
        @param claimInfo   [0] = Total Claimed
                           [1] = Interest Claimed
                           [2] = Principal Claimed
                           [3] = Fee Claimed
                           [4] = Excess Returned Claimed
                           [5] = Amount Recovered (from Liquidation)
                           [6] = Default Suffered
        @param delegateFee Portion of interest (basis points) that goes to the Pool Delegate
        @param stakingFee  Portion of interest (basis points) that goes to the StakeLocker
        @return poolDelegatePortion Total funds to send to Pool Delegate
        @return stakeLockerPortion  Total funds to send to StakeLocker
        @return principalClaim      Total principal claim
        @return interestClaim       Total interest claim
    */
    function calculateClaimAndPortions(
        uint256[7] calldata claimInfo,
        uint256 delegateFee,
        uint256 stakingFee
    ) 
        external
        returns (
            uint256 poolDelegatePortion,
            uint256 stakeLockerPortion,
            uint256 principalClaim,
            uint256 interestClaim
        ) 
    { 
        poolDelegatePortion = claimInfo[1].mul(delegateFee).div(10_000).add(claimInfo[3]);  // PD portion of interest plus fee
        stakeLockerPortion  = claimInfo[1].mul(stakingFee).div(10_000);                     // SL portion of interest

        principalClaim = claimInfo[2].add(claimInfo[4]).add(claimInfo[5]);                                     // Principal + excess + amountRecovered
        interestClaim  = claimInfo[1].sub(claimInfo[1].mul(delegateFee).div(10_000)).sub(stakeLockerPortion);  // Leftover interest
    }

    /**
        @dev Check whether the deactivation is allowed or not.
        @param  globals        Globals contract interface
        @param  principalOut   Amount of funds that is already funded to loans.
        @param  liquidityAsset Liquidity Asset of the pool 
     */
    function validateDeactivation(IGlobals globals, uint256 principalOut, address liquidityAsset) public view {
        require(principalOut <= convertFromUsd(globals, liquidityAsset, 100), "Pool:PRINCIPAL_OUTSTANDING");
    }

    /********************************************/
    /*** Liquidity Provider Utility Functions ***/
    /********************************************/

    /** 
        @dev Calculate the amount of funds to deduct from total claimable amount based on how
             the effective length of time a user has been in a pool. This is a linear decrease
             until block.timestamp - depositDate[who] >= penaltyDelay, after which it returns 0.
        @param  lockupPeriod Timeperiod during which all funds are locked
        @param  penaltyDelay After this timestamp there is no penalty
        @param  amt          Amount to calculate penalty for (all interest plus portion of principal) 
        @param  depositDate  Weighted timestamp representing effective deposit date
        @return penalty Total penalty
    */
    function calcWithdrawPenalty(uint256 lockupPeriod, uint256 penaltyDelay, uint256 amt, uint256 depositDate) public view returns (uint256 penalty) {
        if (lockupPeriod < penaltyDelay) {
            uint256 dTime    = block.timestamp.sub(depositDate);
            uint256 unlocked = dTime.mul(amt).div(penaltyDelay);

            penalty = unlocked > amt ? 0 : amt - unlocked;
        }
    }

    /**
        @dev Update the effective deposit date based on how much new capital has been added.
             If more capital is added, the depositDate moves closer to the current timestamp.
        @param  depositDate Weighted timestamp representing effective deposit date
        @param  balance     Balance of PoolFDT tokens of user
        @param  amt         Total deposit amount
        @param  who         Address of user depositing
    */
    function updateDepositDate(mapping(address => uint256) storage depositDate, uint256 balance, uint256 amt, address who) internal {
        uint256 prevDate = depositDate[who];
        uint256 newDate = block.timestamp;
        if (prevDate == uint256(0)) {
            depositDate[who] = newDate;
        } else {
            uint256 dTime    = block.timestamp.sub(prevDate);
            newDate          = prevDate.add(dTime.mul(amt).div(balance + amt));  // prevDate + (now - prevDate) * (amt / (balance + amt))
            depositDate[who] = newDate;
        }
        emit DepositDateUpdated(who, newDate);
    }

    /**
        @dev View function to indicate if cooldown period has passed for msg.sender
    */
    function isCooldownFinished(uint256 _depositCooldown, IGlobals globals) public view {
        require(_depositCooldown != uint256(0), "Pool:COOLDOWN_NOT_SET");
        require(block.timestamp > _depositCooldown + globals.cooldownPeriod(), "Pool:COOLDOWN_NOT_FINISHED");
    }

    /**
        @dev Performing some checks before doing actual transfers.
    */
    function prepareTransfer(
        mapping(address => uint256) storage depositCooldown,
        mapping(address => uint256) storage depositDate,
        address from,
        address to,
        uint256 wad,
        IGlobals globals,
        uint256 toBalance
    ) external {
        // If transferring in or out of yield farming contract, do not update depositDate
        if (!globals.isStakingRewards(from) && !globals.isStakingRewards(to)) {
            isCooldownFinished(depositCooldown[from], globals);
            depositCooldown[from] = uint256(0);
            updateDepositDate(depositDate, toBalance, wad, to);
        }
    }

    /**
        @dev Signal to withdraw the funds from the pool.
     */
    function intendToWithdraw(mapping(address => uint256) storage depositCooldown, uint256 balance) external {
        require(balance != uint256(0), "Pool:ZERO_BALANCE");
        depositCooldown[msg.sender] = block.timestamp;
        emit Cooldown(msg.sender);
    }

    /**********************************/
    /*** Governor Utility Functions ***/
    /**********************************/

    /**
        @dev Transfer any locked funds to the governor.
        @param token Address of the token that need to reclaimed.
        @param liquidityAsset Address of liquidity asset that is supported by the pool.
        @param globals Instance of the `MapleGlobals` contract.
     */
    function reclaimERC20(address token, address liquidityAsset, IGlobals globals) external {
        require(msg.sender == globals.governor(), "Pool:UNAUTHORIZED");
        require(token != liquidityAsset && token != address(0), "Pool:INVALID_TOKEN");
        IERC20(token).safeTransfer(msg.sender, IERC20(token).balanceOf(address(this)));
    }

    /************************/
    /*** Getter Functions ***/
    /************************/

    /// @dev Official balancer pool bdiv() function, does synthetic float with 10^-18 precision
    function bdiv(uint256 a, uint256 b) public pure returns (uint256) {
        require(b != 0, "ERR_DIV_ZERO");
        uint256 c0 = a * WAD;
        require(a == 0 || c0 / a == WAD, "ERR_DIV_INTERNAL"); // bmul overflow
        uint256 c1 = c0 + (b / 2);
        require(c1 >= c0, "ERR_DIV_INTERNAL"); //  badd require
        uint256 c2 = c1 / b;
        return c2;
    }

    /** 
        @dev Calculates the value of BPT in units of liquidityAsset.
        @param _bPool         Address of Balancer pool
        @param liquidityAsset Asset used by Pool for liquidity to fund loans
        @param staker         Address that deposited BPTs to stakeLocker
        @param stakeLocker    Escrows BPTs deposited by staker
        @return USDC value of staker BPTs
    */
    function BPTVal(
        address _bPool,
        address liquidityAsset,
        address staker,
        address stakeLocker
    ) public view returns (uint256) {

        // Create interfaces for the balancerPool as a Pool and as an ERC-20 token
        IBPool bPool      = IBPool(_bPool);
        IERC20 bPoolERC20 = IERC20(_bPool);

        // FDTs are minted 1:1 (in wei) in the StakeLocker when staking BPTs, thus representing stake amount.
        // These are burned when withdrawing staked BPTs, thus representing the current stake amount.
        uint256 amountStakedBPT       = IERC20(stakeLocker).balanceOf(staker);
        uint256 totalSupplyBPT        = bPoolERC20.totalSupply();
        uint256 liquidityAssetBalance = bPool.getBalance(liquidityAsset);
        uint256 liquidityAssetWeight  = bPool.getNormalizedWeight(liquidityAsset);

        // liquidityAsset value = (amountStaked/totalSupply) * (liquidityAssetBalance/liquidityAssetWeight)
        return bdiv(amountStakedBPT, totalSupplyBPT).mul(bdiv(liquidityAssetBalance, liquidityAssetWeight)).div(WAD);
    }

    /** 
        @dev Calculate liquidityAsset swap out value of staker BPT balance escrowed in stakeLocker.
        @param _bPool          Balancer pool that issues the BPTs
        @param liquidityAsset  Swap out asset (e.g. USDC) to receive when burning BPTs
        @param staker          Address that deposited BPTs to stakeLocker
        @param stakeLocker     Escrows BPTs deposited by staker
        @return liquidityAsset Swap out value of staker BPTs
    */
    function getSwapOutValue(
        address _bPool,
        address liquidityAsset,
        address staker,
        address stakeLocker
    ) public view returns (uint256) {

        // Fetch balancer pool token information
        IBPool bPool            = IBPool(_bPool);
        uint256 tokenBalanceOut = bPool.getBalance(liquidityAsset);
        uint256 tokenWeightOut  = bPool.getDenormalizedWeight(liquidityAsset);
        uint256 poolSupply      = bPool.totalSupply();
        uint256 totalWeight     = bPool.getTotalDenormalizedWeight();
        uint256 swapFee         = bPool.getSwapFee();

        // Fetch amount staked in stakeLocker by staker
        uint256 poolAmountIn = IERC20(stakeLocker).balanceOf(staker);

        // Returns the amount of liquidityAsset that can be recovered from BPT burning
        uint256 tokenAmountOut = bPool.calcSingleOutGivenPoolIn(
            tokenBalanceOut,
            tokenWeightOut,
            poolSupply,
            totalWeight,
            poolAmountIn,
            swapFee
        );

        // Max amount that can be swapped based on amount of liquidtyAsset in the Balancer Pool
        uint256 maxSwapOut = tokenBalanceOut.mul(bPool.MAX_OUT_RATIO()).div(WAD);  

        return tokenAmountOut <= maxSwapOut ? tokenAmountOut : maxSwapOut;
    }

    /** 
        @dev Calculate liquidityAsset swap out value of entire BPT balance escrowed in stakeLocker.
        @param _bPool          Balancer pool that issues the BPTs
        @param liquidityAsset  Swap out asset (e.g. USDC) to receive when burning BPTs
        @param stakeLocker     Escrows BPTs deposited by staker
        @return liquidityAsset Swap out value of StakeLocker BPTs
    */
    function getSwapOutValueLocker(
        address _bPool,
        address liquidityAsset,
        address stakeLocker
    ) public view returns (uint256) {

        // Fetch balancer pool token information
        IBPool bPool            = IBPool(_bPool);
        uint256 tokenBalanceOut = bPool.getBalance(liquidityAsset);
        uint256 tokenWeightOut  = bPool.getDenormalizedWeight(liquidityAsset);
        uint256 poolSupply      = bPool.totalSupply();
        uint256 totalWeight     = bPool.getTotalDenormalizedWeight();
        uint256 swapFee         = bPool.getSwapFee();

        // Fetch entire BPT balance of stakeLocker
        uint256 poolAmountIn = bPool.balanceOf(stakeLocker);

        // Returns the amount of liquidityAsset that can be recovered from BPT burning
        uint256 tokenAmountOut = bPool.calcSingleOutGivenPoolIn(
            tokenBalanceOut,
            tokenWeightOut,
            poolSupply,
            totalWeight,
            poolAmountIn,
            swapFee
        );

        // Max amount that can be swapped based on amount of liquidtyAsset in the Balancer Pool
        uint256 maxSwapOut = tokenBalanceOut.mul(bPool.MAX_OUT_RATIO()).div(WAD);  

        return tokenAmountOut <= maxSwapOut ? tokenAmountOut : maxSwapOut;
    }

    /**
        @dev Calculates BPTs required if burning BPTs for liquidityAsset, given supplied tokenAmountOutRequired.
        @param  _bPool                       Balancer pool that issues the BPTs
        @param  liquidityAsset               Swap out asset (e.g. USDC) to receive when burning BPTs
        @param  staker                       Address that deposited BPTs to stakeLocker
        @param  stakeLocker                  Escrows BPTs deposited by staker
        @param  liquidityAssetAmountRequired Amount of liquidityAsset required to recover
        @return [0] = poolAmountIn required
                [1] = poolAmountIn currently staked
    */
    function getPoolSharesRequired(
        address _bPool,
        address liquidityAsset,
        address staker,
        address stakeLocker,
        uint256 liquidityAssetAmountRequired
    ) public view returns (uint256, uint256) {

        IBPool bPool = IBPool(_bPool);

        uint256 tokenBalanceOut = bPool.getBalance(liquidityAsset);
        uint256 tokenWeightOut  = bPool.getDenormalizedWeight(liquidityAsset);
        uint256 poolSupply      = bPool.totalSupply();
        uint256 totalWeight     = bPool.getTotalDenormalizedWeight();
        uint256 swapFee         = bPool.getSwapFee();

        // Fetch amount of BPTs required to burn to receive liquidityAssetAmountRequired
        uint256 poolAmountInRequired = bPool.calcPoolInGivenSingleOut(
            tokenBalanceOut,
            tokenWeightOut,
            poolSupply,
            totalWeight,
            liquidityAssetAmountRequired,
            swapFee
        );

        // Fetch amount staked in stakeLocker by staker
        uint256 stakerBalance = IERC20(stakeLocker).balanceOf(staker);

        return (poolAmountInRequired, stakerBalance);
    }

    /**
        @dev Returns information on the stake requirements.
        @param  globals        Interface of MapleGlobals
        @param  balancerPool   Address of Balancer pool
        @param  liquidityAsset Address of liquidityAsset, to be returned from swap out
        @param  poolDelegate   Address of Pool Delegate
        @param  stakeLocker    Address of StakeLocker
        @return swapOutAmountRequired      Min amount of liquidityAsset coverage from staking required (in liquidityAsset units)
        @return currentPoolDelegateCover   Present amount of liquidityAsset coverage from Pool Delegate stake (in liquidityAsset units)
        @return enoughStakeForFinalization If enough stake is present from Pool Delegate for Pool finalization
        @return poolAmountInRequired       BPTs required for minimum liquidityAsset coverage
        @return poolAmountPresent          Current staked BPTs
    */
    function getInitialStakeRequirements(IGlobals globals, address balancerPool, address liquidityAsset, address poolDelegate, address stakeLocker) public view returns (
        uint256 swapOutAmountRequired,
        uint256 currentPoolDelegateCover,
        bool    enoughStakeForFinalization,
        uint256 poolAmountInRequired,
        uint256 poolAmountPresent
    ) {
        swapOutAmountRequired = convertFromUsd(globals, liquidityAsset, globals.swapOutRequired());
        (
            poolAmountInRequired,
            poolAmountPresent
        ) = getPoolSharesRequired(balancerPool, liquidityAsset, poolDelegate, stakeLocker, swapOutAmountRequired);

        currentPoolDelegateCover   = getSwapOutValue(balancerPool, liquidityAsset, poolDelegate, stakeLocker);
        enoughStakeForFinalization = poolAmountPresent >= poolAmountInRequired;
    }

    /**
        @dev View claimable balance from LiqudityLocker (reflecting deposit + gain/loss).
        @param  withdrawableFundsOfLp  FDT withdrawableFundsOf LP
        @param  depositDateForLp       LP deposit date
        @param  lockupPeriod           Pool lockup period
        @param  penaltyDelay           Pool penalty delay
        @param  balanceOfLp            LP FDT balance
        @param  principalPenalty       Principal penalty percentage
        @param  liquidityAssetDecimals Decimals of liquidityAsset
        @return total     Total     amount claimable
        @return principal Principal amount claimable
        @return interest  Interest  amount claimable
    */
    // TODO: Consider renaming this - could be mistaken for Pool claimable funds, not LP claimable
    function claimableFunds(
        uint256 withdrawableFundsOfLp,
        uint256 depositDateForLp,
        uint256 lockupPeriod,
        uint256 penaltyDelay,
        uint256 balanceOfLp,
        uint256 principalPenalty,
        uint256 liquidityAssetDecimals
    ) 
        public
        view
        returns(
            uint256 total,
            uint256 principal,
            uint256 interest
        ) 
    {
        interest = withdrawableFundsOfLp;
        // Deposit is still within lockupPeriod, user has 0 claimable principal under this condition.
        if (depositDateForLp.add(lockupPeriod) > block.timestamp) total = interest; 
        else {
            uint256 userBalance  = fromWad(balanceOfLp, liquidityAssetDecimals);
            uint256 firstPenalty = principalPenalty.mul(userBalance).div(10000);                                                   // Calculate flat principal penalty
            uint256 totalPenalty = calcWithdrawPenalty(lockupPeriod, penaltyDelay, interest.add(firstPenalty), depositDateForLp);  // Calculate total penalty

            principal = userBalance.sub(totalPenalty);
            total     = principal.add(interest);
        }
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    /**
        @dev Utility to convert from WAD precision to liquidtyAsset precision.
        @param amt Amount to convert
        @param liquidityAssetDecimals Liquidity asset decimal
    */
    function fromWad(uint256 amt, uint256 liquidityAssetDecimals) public view returns(uint256) {
        return amt.mul(10 ** liquidityAssetDecimals).div(WAD);
    }

    /** 
        @dev Internal helper function to return an interface of MapleGlobals.
        @param  poolFactory Factory that deployed the Pool,  stores MapleGlobals
        @return Interface of MapleGlobals
    */
    function _globals(address poolFactory) internal view returns (IGlobals) {
        return IGlobals(ILoanFactory(poolFactory).globals());
    }

    /** 
        @dev Function to return liquidityAsset in liquidityAsset units when given integer USD (E.g., $100 = 100).
        @param  globals        Globals contract interface
        @param  liquidityAsset Liquidity Asset of the pool 
        @param  usdAmount      USD amount to convert, in integer units (e.g., $100 = 100)
        @return usdAmount worth of liquidityAsset, in liquidityAsset units
    */
    function convertFromUsd(IGlobals globals, address liquidityAsset, uint256 usdAmount) internal view returns (uint256) {
        return usdAmount
            .mul(10 ** 8)                                         // Cancel out 10 ** 8 decimals from oracle
            .mul(10 ** IERC20Details(liquidityAsset).decimals())  // Convert to liquidityAsset precision
            .div(globals.getLatestPrice(liquidityAsset));         // Convert to liquidityAsset value
    }
}
