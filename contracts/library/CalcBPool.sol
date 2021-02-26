// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../interfaces/ILoan.sol";
import "../interfaces/IBPool.sol";
import "../interfaces/IGlobals.sol";
import "../interfaces/ILiquidityLocker.sol";
import "../interfaces/IERC20Details.sol";
import "../interfaces/ILoanFactory.sol";
import "../interfaces/IStakeLocker.sol";
import "../interfaces/IDebtLockerFactory.sol";

library CalcBPool {

    using SafeMath for uint256;

    uint256 public constant MAX_UINT256 = uint256(-1);
    uint256 public constant WAD         = 10 ** 18;
    uint8   public constant DL_FACTORY  = 1;         // Factory type of `DebtLockerFactory`.

    event LoanFunded(address indexed loan, address debtLocker, uint256 amountFunded);

    /// @dev Official balancer pool bdiv() function, does synthetic float with 10^-18 precision.
    function bdiv(uint256 a, uint256 b) public pure returns (uint256) {
        require(b != 0, "ERR_DIV_ZERO");
        uint256 c0 = a * WAD;
        require(a == 0 || c0 / a == WAD, "ERR_DIV_INTERNAL"); // bmul overflow
        uint256 c1 = c0 + (b / 2);
        require(c1 >= c0, "ERR_DIV_INTERNAL"); //  badd require
        uint256 c2 = c1 / b;
        return c2;
    }

    /// @dev Calculates the value of BPT in units of _liquidityAssetContract in 'wei' (decimals) for this token.
    // TODO: Identify use and add NatSpec later.
    function BPTVal(
        address _pool,
        address _pair,
        address _staker,
        address _stakeLocker
    ) public view returns (uint256) {

        //calculates the value of BPT in unites of _liquidityAssetContract, in 'wei' (decimals) for this token

        // Create interfaces for the balancerPool as a Pool and as an ERC-20 token.
        IBPool bPool = IBPool(_pool);
        IERC20 bPoolERC20 = IERC20(_pool);

        // FDTs are minted 1:1 (in wei) in the StakeLocker when staking BPTs, thus representing stake amount.
        // These are burned when withdrawing staked BPTs, thus representing the current stake amount.
        uint256 amountStakedBPT = IERC20(_stakeLocker).balanceOf(_staker);
        uint256 totalSupplyBPT = bPoolERC20.totalSupply();
        uint256 liquidityAssetBalance = bPool.getBalance(_pair);
        uint256 liquidityAssetWeight = bPool.getNormalizedWeight(_pair);
        uint256 _val = bdiv(amountStakedBPT, totalSupplyBPT).mul(bdiv(liquidityAssetBalance, liquidityAssetWeight)).div(WAD);
        
        //we have to divide out the extra WAD with normal safemath
        //the two divisions must be separate, as coins that are lower decimals(like usdc) will underflow and give 0
        //due to the fact that the _liquidityAssetWeight is a synthetic float from bpool, IE  x*10^18 where 0<x<1
        //the result here is
        return _val;
    }

    /** 
        @dev Calculate _pair swap out value of staker BPT balance escrowed in stakeLocker.
        @param pool        Balancer pool that issues the BPTs.
        @param pair        Swap out asset (e.g. USDC) to receive when burning BPTs.
        @param staker      Address that deposited BPTs to stakeLocker.
        @param stakeLocker Escrows BPTs deposited by staker.
        @return USDC swap out value of staker BPTs.
    */
    function getSwapOutValue(
        address pool,
        address pair,
        address staker,
        address stakeLocker
    ) public view returns (uint256) {

        // Fetch balancer pool token information.
        IBPool bPool            = IBPool(pool);
        uint256 tokenBalanceOut = bPool.getBalance(pair);
        uint256 tokenWeightOut  = bPool.getDenormalizedWeight(pair);
        uint256 poolSupply      = bPool.totalSupply();
        uint256 totalWeight     = bPool.getTotalDenormalizedWeight();
        uint256 swapFee         = bPool.getSwapFee();

        // Fetch amount staked in stakeLocker by staker.
        uint256 poolAmountIn = IERC20(stakeLocker).balanceOf(staker);

        // Returns amount of BPTs required to extract tokenAmountOut.
        uint256 tokenAmountOut = bPool.calcSingleOutGivenPoolIn(
            tokenBalanceOut,
            tokenWeightOut,
            poolSupply,
            totalWeight,
            poolAmountIn,
            swapFee
        );

        return tokenAmountOut;
    }

    /** 
        @dev Calculate _pair swap out value of staker BPT balance escrowed in stakeLocker.
        @param pool        Balancer pool that issues the BPTs.
        @param pair        Swap out asset (e.g. USDC) to receive when burning BPTs.
        @param stakeLocker Escrows BPTs deposited by staker.
        @return USDC swap out value of staker BPTs.
    */
    function getSwapOutValueLocker(
        address pool,
        address pair,
        address stakeLocker
    ) public view returns (uint256) {

        // Fetch balancer pool token information.
        IBPool bPool            = IBPool(pool);
        uint256 tokenBalanceOut = bPool.getBalance(pair);
        uint256 tokenWeightOut  = bPool.getDenormalizedWeight(pair);
        uint256 poolSupply      = bPool.totalSupply();
        uint256 totalWeight     = bPool.getTotalDenormalizedWeight();
        uint256 swapFee         = bPool.getSwapFee();

        // Fetch BPT balance of stakeLocker by staker.
        uint256 poolAmountIn = bPool.balanceOf(stakeLocker);

        // Returns amount of BPTs required to extract tokenAmountOut.
        uint256 tokenAmountOut = bPool.calcSingleOutGivenPoolIn(
            tokenBalanceOut,
            tokenWeightOut,
            poolSupply,
            totalWeight,
            poolAmountIn,
            swapFee
        );

        return tokenAmountOut;
    }

    /**
        @dev Calculates BPTs required if burning BPTs for pair, given supplied tokenAmountOutRequired.
        @param  bpool              Balancer pool that issues the BPTs.
        @param  pair               Swap out asset (e.g. USDC) to receive when burning BPTs.
        @param  staker             Address that deposited BPTs to stakeLocker.
        @param  stakeLocker        Escrows BPTs deposited by staker.
        @param  pairAmountRequired Amount of pair tokens out required.
        @return [0] = poolAmountIn required
                [1] = poolAmountIn currently staked.
    */
    function getPoolSharesRequired(
        address bpool,
        address pair,
        address staker,
        address stakeLocker,
        uint256 pairAmountRequired
    ) public view returns (uint256, uint256) {

        IBPool bPool = IBPool(bpool);

        uint256 tokenBalanceOut = bPool.getBalance(pair);
        uint256 tokenWeightOut  = bPool.getDenormalizedWeight(pair);
        uint256 poolSupply      = bPool.totalSupply();
        uint256 totalWeight     = bPool.getTotalDenormalizedWeight();
        uint256 swapFee         = bPool.getSwapFee();

        // Fetch amount of BPTs required to burn to receive pairAmountRequired.
        uint256 poolAmountInRequired = bPool.calcPoolInGivenSingleOut(
            tokenBalanceOut,
            tokenWeightOut,
            poolSupply,
            totalWeight,
            pairAmountRequired,
            swapFee
        );

        // Fetch amount staked in _stakeLocker by staker.
        uint256 stakerBalance = IERC20(stakeLocker).balanceOf(staker);

        return (poolAmountInRequired, stakerBalance);
    }

    /**
        @dev Returns information on the stake requirements.
        @return swapOutAmountRequired      Min amount of liquidityAsset coverage from staking required.
        @return amountRecoveredFromStaking Present amount of liquidityAsset coverage from staking.
        @return enoughStakeForFinalization If enough stake is present from Pool Delegate for finalization.
        @return poolAmountInRequired       BPTs required for minimum liquidityAsset coverage.
        @return poolAmountPresent          Current staked BPTs.
    */
    function getInitialStakeRequirements(IGlobals globals, address balancerPool, address swapOutAsset, address poolDelegate, address stakeLocker) public view returns (
        uint256 swapOutAmountRequired,
        uint256 amountRecoveredFromStaking,
        bool enoughStakeForFinalization,
        uint256 poolAmountInRequired,
        uint256 poolAmountPresent
    ) {
        swapOutAmountRequired = globals.swapOutRequired() * (10 ** IERC20Details(swapOutAsset).decimals());
        (
            poolAmountInRequired,
            poolAmountPresent
        ) = getPoolSharesRequired(balancerPool, swapOutAsset, poolDelegate, stakeLocker, swapOutAmountRequired);

        amountRecoveredFromStaking = getSwapOutValue(balancerPool, swapOutAsset, poolDelegate, stakeLocker);
        enoughStakeForFinalization = poolAmountPresent >= poolAmountInRequired;
    }

    /**
        @dev Fund a loan for amt, utilize the supplied dlFactory for debt lockers.
        @param  loan      Address of the loan to fund.
        @param  dlFactory The debt locker factory to utilize.
        @param  amt       Amount to fund the loan.
    */
    function fundLoan(
        mapping(address => mapping(address => address)) storage debtLockers,
        address superFactory,
        address liquidityLocker,
        address loan,
        address dlFactory,
        uint256 amt
    ) external {
        IGlobals globals = _globals(superFactory);
        // Auth checks.
        require(globals.isValidLoanFactory(ILoan(loan).superFactory()),         "Pool:INVALID_LOAN_FACTORY");
        require(ILoanFactory(ILoan(loan).superFactory()).isLoan(loan),          "Pool:INVALID_LOAN");
        require(globals.isValidSubFactory(superFactory, dlFactory, DL_FACTORY), "Pool:INVALID_DL_FACTORY");

        address _debtLocker = debtLockers[loan][dlFactory];

        // Instantiate locker if it doesn't exist with this factory type.
        if (_debtLocker == address(0)) {
            address debtLocker = IDebtLockerFactory(dlFactory).newLocker(loan);
            debtLockers[loan][dlFactory] = debtLocker;
            _debtLocker = debtLocker;
        }
    
        // Fund loan.
        ILiquidityLocker(liquidityLocker).fundLoan(loan, _debtLocker, amt);
        
        emit LoanFunded(loan, _debtLocker, amt);
    }

    /**
        @dev Helper function for claim() if a default has occurred.
     */
    function handleDefault(
        IERC20 liquidityAsset,
        address stakeLocker,
        address stakeAsset,
        address loan,
        uint256 defaultSuffered
    ) 
        external
        returns
        (
            uint256 bptsBurned,
            uint256 bptsReturned,
            uint256 liquidityAssetRecoveredFromBurn
        ) 
    {

        // Check liquidityAsset swapOut value of StakeLocker coverage
        uint256 availableSwapOut = getSwapOutValueLocker(stakeAsset, address(liquidityAsset), stakeLocker);
        uint256 maxSwapOut       = liquidityAsset.balanceOf(stakeAsset).mul(IBPool(stakeAsset).MAX_OUT_RATIO()).div(WAD);  // Max amount that can be swapped 

        availableSwapOut = availableSwapOut > maxSwapOut ? maxSwapOut : availableSwapOut;

        // Pull BPTs from StakeLocker.
        require(
            IStakeLocker(stakeLocker).pull(address(this), IBPool(stakeAsset).balanceOf(stakeLocker)),
            "Pool:STAKE_PULL"
        );

        // To maintain accounting, account for accidental transfers into Pool
        uint256 preBurnBalance = liquidityAsset.balanceOf(address(this));

        // Burn enough BPTs for liquidityAsset to cover defaultSuffered.
        bptsBurned = IBPool(stakeAsset).exitswapExternAmountOut(
                        address(liquidityAsset), 
                        availableSwapOut >= defaultSuffered ? defaultSuffered : availableSwapOut, 
                        MAX_UINT256
                    );

        // Return remaining BPTs to stakeLocker.
        bptsReturned = IBPool(stakeAsset).balanceOf(address(this));
        IBPool(stakeAsset).transfer(stakeLocker, bptsReturned);
        liquidityAssetRecoveredFromBurn = liquidityAsset.balanceOf(address(this)).sub(preBurnBalance);
    }

    /**
        @dev Helper function to calculate the fee and claim portion.
    */
    function calculateClaimAndPortions(
        uint256[7] calldata claimInfo,
        uint256 delegateFee,
        uint256 stakingFee
    ) 
        external
        returns
        (
            uint256 poolDelegatePortion,
            uint256 stakeLockerPortion,
            uint256 principalClaim,
            uint256 interestClaim
        ) 
    { 
        poolDelegatePortion = claimInfo[1].mul(delegateFee).div(10000).add(claimInfo[3]);  // PD portion of interest plus fee
        stakeLockerPortion  = claimInfo[1].mul(stakingFee).div(10000);                     // SL portion of interest

        principalClaim = claimInfo[2].add(claimInfo[4]).add(claimInfo[5]);                                    // Principal + excess + amountRecovered
        interestClaim  = claimInfo[1].sub(claimInfo[1].mul(delegateFee).div(10000)).sub(stakeLockerPortion);  // Leftover interest
    }

    /** 
        @dev Calculate the amount of funds to deduct from total claimable amount based on how
             the effective length of time a user has been in a pool. This is a linear decrease
             until block.timestamp - depositDate[who] >= penaltyDelay, after which it returns 0.
        @param  lockupPeriod Timeperiod till funds get locked.
        @param  penaltyDelay After this timestamp there is no penalty.
        @param  amt          Total claimable amount 
        @param  depositDate  Weighted timestamp at which `who` deposit funds.
        @return penalty Total penalty
    */
    function calcWithdrawPenalty(uint256 lockupPeriod, uint256 penaltyDelay, uint256 amt, uint256 depositDate) external view returns (uint256 penalty) {
        if (lockupPeriod < penaltyDelay) {
            uint256 dTime    = block.timestamp.sub(depositDate);
            uint256 unlocked = dTime.mul(amt).div(penaltyDelay);

            penalty = unlocked > amt ? 0 : amt - unlocked;
        }
    }

    /**
        @dev Update the effective deposit date based on how much new capital has been added.
             If more capital is added, the depositDate moves closer to the current timestamp.
        @param  depositDate Weighted timestamp at which `who` deposit funds.
        @param  balance     Balance of PoolFDT tokens for given `who`.
        @param  amt         Total deposit amount.
        @param  who         Address of user depositing.
    */
    function updateDepositDate(mapping(address => uint256) storage depositDate, uint256 balance, uint256 amt, address who) internal {
        if (depositDate[who] == 0) {
            depositDate[who] = block.timestamp;
        } else {
            uint256 depDate  = depositDate[who];
            uint256 coef     = (WAD.mul(amt)).div(balance + amt);
            depositDate[who] = (depDate.mul(WAD).add((block.timestamp.sub(depDate)).mul(coef))).div(WAD);  // depDate + (now - depDate) * coef
        }
    }

    function _globals(address poolFactory) internal view returns (IGlobals) {
        return IGlobals(ILoanFactory(poolFactory).globals());
    }
    
}
