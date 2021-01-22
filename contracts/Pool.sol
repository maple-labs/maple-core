// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "./math/CalcBPool.sol";
import "./interfaces/ILoan.sol";
import "./interfaces/IBPool.sol";
import "./interfaces/IGlobals.sol";
import "./interfaces/ILoanFactory.sol";
import "./interfaces/IPoolFactory.sol";
import "./interfaces/IStakeLocker.sol";
import "./interfaces/IStakeLockerFactory.sol";
import "./interfaces/ILiquidityLocker.sol";
import "./interfaces/ILiquidityLockerFactory.sol";
import "./interfaces/IDebtLockerFactory.sol";
import "./interfaces/IDebtLocker.sol";
import "./token/FDT.sol";

/// @title Pool is the core contract for liquidity pools.
contract Pool is FDT, CalcBPool {

    using SafeMath for uint256;

    IERC20  public immutable liquidityAsset;   // The asset deposited by lenders into the LiquidityLocker, for funding loans.

    address public immutable poolDelegate;     // The pool delegate, who maintains full authority over this Pool.
    address public immutable liquidityLocker;  // The LiquidityLocker owned by this contract.
    address public immutable stakeAsset;       // The asset deposited by stakers into the StakeLocker, for liquidation during default events.
    address public immutable stakeLocker;      // Address of the StakeLocker, escrowing the staked asset.
    address public immutable slFactory;        // Address of the StakeLocker factory.
    address public immutable superFactory;     // The factory that deployed this Loan.

    uint256 private immutable liquidityAssetDecimals;  // decimals() precision for the liquidityAsset.

    uint256 public principalOut;      // Sum of all outstanding principal on loans
    uint256 public interestSum;       // Sum of all interest currently inside the liquidity locker
    uint256 public stakingFee;        // The fee for stakers (in basis points).
    uint256 public delegateFee;       // The fee for delegates (in basis points).
    uint256 public principalPenalty;  // Max penalty on principal in bips on early withdrawal.
    uint256 public penaltyDelay;      // Time until total interest is available after a deposit, in seconds.
    uint256 public liquidityCap;      // Amount of liquidity tokens accepted by the pool.

    enum State { Initialized, Finalized, Deactivated }
    State public poolState;  // The current state of this pool.

    mapping(address => uint256)                     public depositDate;  // Used for interest penalty calculation
    mapping(address => mapping(address => address)) public debtLockers;  // loans[LOAN_VAULT][LOCKER_FACTORY] = DebtLocker

    event LoanFunded(address loan, address debtLocker, uint256 amountFunded);
    event BalanceUpdated(address who, address token, uint256 balance);
    event Claim(address loan, uint interest, uint principal, uint fee);

    /**
        @dev Constructor for a Pool.
        @param  _poolDelegate   The address that has manager privlidges for the Pool.
        @param  _liquidityAsset The asset escrowed in LiquidityLocker.
        @param  _stakeAsset     The asset escrowed in StakeLocker.
        @param  _slFactory      Factory used to instantiate StakeLocker.
        @param  _llFactory      Factory used to instantiate LiquidityLocker.
        @param  _stakingFee     Fee that stakers earn on interest, in bips.
        @param  _delegateFee    Fee that _poolDelegate earns on interest, in bips.
        @param  _liquidityCap   Amount of liquidity tokens accepted by the pool.
        @param  name            Name of pool token.
        @param  symbol          Symbol of pool token.
    */
    constructor(
        address _poolDelegate,
        address _liquidityAsset,
        address _stakeAsset,
        address _slFactory,
        address _llFactory,
        uint256 _stakingFee,
        uint256 _delegateFee,
        uint256 _liquidityCap,
        string memory name,
        string memory symbol
    ) FDT(name, symbol, _liquidityAsset) public {
        require(IGlobals(_globals).isValidLoanAsset(_liquidityAsset), "Pool:LIQ_ASSET_NOT_WHITELISTED");
        require(_liquidityCap   != uint256(0),                        "Pool:INVALID_CAP");

        address[] memory tokens = IBPool(_stakeAsset).getFinalTokens();

        uint256  i = 0;
        bool valid = false;

        // Check that one of the assets in balancer pool is the liquidity asset
        while(i < tokens.length && !valid) { valid = tokens[i] == _liquidityAsset; i++; }  

        require(valid, "Pool:INVALID_STAKING_POOL");

        // Assign variables relating to the LiquidityAsset.
        liquidityAsset         = IERC20(_liquidityAsset);
        liquidityAssetDecimals = ERC20(_liquidityAsset).decimals();

        // Assign misc. state variables.
        stakeAsset   = _stakeAsset;
        slFactory    = _slFactory;
        poolDelegate = _poolDelegate;
        stakingFee   = _stakingFee;
        delegateFee  = _delegateFee;
        superFactory = msg.sender;
        liquidityCap = _liquidityCap;

        // Initialize the LiquidityLocker and StakeLocker.
        stakeLocker     = createStakeLocker(_stakeAsset, _slFactory, _liquidityAsset, _globals(msg.sender));
        liquidityLocker = address(ILiquidityLockerFactory(_llFactory).newLocker(_liquidityAsset));

        // Withdrawal penalty default settings.
        principalPenalty = 500;
        penaltyDelay     = 30 days;
    }

    modifier isState(State _state) {
        require(poolState == _state, "Pool:STATE_CHECK");
        _;
    }

    modifier isDelegate() {
        require(msg.sender == poolDelegate, "Pool:MSG_SENDER_NOT_DELEGATE");
        _;
    }

    function _globals(address poolFactory) internal view returns (IGlobals) {
        return IGlobals(ILoanFactory(poolFactory).globals());
    }

    /**
        @dev Deploys and assigns a StakeLocker for this Pool (only used once in constructor).
        @param stakeAsset     Address of the asset used for staking.
        @param slFactory      Address of the StakeLocker factory used for instantiation.
        @param liquidityAsset Address of the liquidity asset, required when burning stakeAsset.
        @param globals        Address of the Maple Globals contract.
    */
    function createStakeLocker(address stakeAsset, address slFactory, address liquidityAsset, IGlobals globals) private returns (address) {
        require(IBPool(stakeAsset).isBound(globals.mpl()) && IBPool(stakeAsset).isFinalized(), "Pool:INVALID_BALANCER_POOL");
        return IStakeLockerFactory(slFactory).newLocker(stakeAsset, liquidityAsset);
    }

    /**
        @dev Finalize the pool, enabling deposits. Checks poolDelegate amount deposited to StakeLocker.
    */
    function finalize() public isDelegate isState(State.Initialized) {
        (,, bool stakePresent,,) = getInitialStakeRequirements();
        require(stakePresent, "Pool:NOT_ENOUGH_STAKE_TO_FINALIZE");
        poolState = State.Finalized;
    }

    /**
        @dev Returns information on the stake requirements.
        @return [0] = Min amount of liquidityAsset coverage from staking required
                [1] = Present amount of liquidityAsset coverage from staking
                [2] = If enough stake is present from Pool Delegate for finalization
                [3] = Staked BPTs required for minimum liquidityAsset coverage
                [4] = Current staked BPTs
    */
    function getInitialStakeRequirements() public view returns (uint256, uint256, bool, uint256, uint256) {

        IGlobals globals = _globals(superFactory);

        address balancerPool = stakeAsset;
        address swapOutAsset = address(liquidityAsset);
        uint256 swapOutAmountRequired = globals.swapOutRequired() * (10 ** liquidityAssetDecimals);

        (
            uint256 poolAmountInRequired, 
            uint256 poolAmountPresent
        ) = this.getPoolSharesRequired(balancerPool, swapOutAsset, poolDelegate, stakeLocker, swapOutAmountRequired);

        return (
            swapOutAmountRequired,
            this.getSwapOutValue(balancerPool, swapOutAsset, poolDelegate, stakeLocker),
            poolAmountPresent >= poolAmountInRequired,
            poolAmountInRequired,
            poolAmountPresent
        );
    }

    // Note: Tether is unusable as a LiquidityAsset!
    /**
        @dev Liquidity providers can deposit LiqudityAsset into the LiquidityLocker, minting FDTs.
        @param amt The amount of LiquidityAsset to deposit, in wei.
    */
    function deposit(uint256 amt) external isState(State.Finalized) {
        require(isDepositAllowed(amt), "Pool:LIQUIDITY_CAP_HIT");
        require(liquidityAsset.transferFrom(msg.sender, liquidityLocker, amt), "Pool:DEPOSIT_TRANSFER_FROM");
        uint256 wad = _toWad(amt);

        updateDepositDate(wad, msg.sender);
        _mint(msg.sender, wad);

        emit BalanceUpdated(liquidityLocker, address(liquidityAsset), _balanceOfLiquidityLocker());
    }

    /**
        @dev Check whether the given `depositAmt` is an acceptable amount by the pool?.
        @param depositAmt Amount of tokens (i.e loanAsset type) is user willing to deposit.
    */
    function isDepositAllowed(uint256 depositAmt) public view returns(bool) {
        uint256 totalDeposits = _balanceOfLiquidityLocker().add(principalOut);
        return totalDeposits.add(depositAmt) <= liquidityCap;
    }

    /**
        @dev Set `liquidityCap`, Only allowed by the pool delegate.
        @param newLiquidityCap New liquidity cap value. 
    */
    function setLiquidityCap(uint256 newLiquidityCap) external isDelegate {
        liquidityCap = newLiquidityCap;
    }

    /**
        @dev Liquidity providers can withdraw LiqudityAsset from the LiquidityLocker, burning FDTs.
        @param amt The amount of LiquidityAsset to withdraw.
    */
    function withdraw(uint256 amt) external {
        uint256 fdtAmt = _toWad(amt);
        require(balanceOf(msg.sender) >= fdtAmt, "Pool:USER_BAL_LT_AMT");

        uint256 allocatedInterest = withdrawableFundsOf(msg.sender);                                     // Calculated interest.
        uint256 priPenalty        = principalPenalty.mul(amt).div(10000);                                // Calculate flat principal penalty.
        uint256 totPenalty        = calcWithdrawPenalty(allocatedInterest.add(priPenalty), msg.sender);  // Get total penalty, however it may be calculated.
        uint256 due               = amt.sub(totPenalty);                                                 // Funds due after the penalty deduction from the `amt` that is asked for withdraw.
        
        _burn(msg.sender, fdtAmt);  // Burn the corresponding FDT balance.
        withdrawFunds();            // Transfer full entitled interest.

        require(ILiquidityLocker(liquidityLocker).transfer(msg.sender, due), "Pool::WITHDRAW_TRANSFER");  // Transfer the principal amount - totPenalty.

        interestSum = interestSum.add(totPenalty);  // Update the `interestSum` with the penalty amount. 
        updateFundsReceived();                      // Update the `pointsPerShare` using this as fundsTokenBalance is incremented by `totPenalty`.

        emit BalanceUpdated(liquidityLocker, address(liquidityAsset), _balanceOfLiquidityLocker());
    }

    /**
        @dev Fund a loan for amt, utilize the supplied dlFactory for debt lockers.
        @param  loan      Address of the loan to fund.
        @param  dlFactory The debt locker factory to utilize.
        @param  amt       Amount to fund the loan.
    */
    function fundLoan(address loan, address dlFactory, uint256 amt) external isState(State.Finalized) isDelegate {

        IGlobals globals = _globals(superFactory);

        // Auth checks.
        require(globals.isValidLoanFactory(ILoan(loan).superFactory()), "Pool:INVALID_LOAN_FACTORY");
        require(ILoanFactory(ILoan(loan).superFactory()).isLoan(loan),  "Pool:INVALID_LOAN");
        require(globals.isValidSubFactory(superFactory, dlFactory, 1),  "Pool:INVALID_DL_FACTORY");

        address _debtLocker = debtLockers[loan][dlFactory];

        // Instantiate locker if it doesn't exist with this factory type.
        if (_debtLocker == address(0)) {
            address debtLocker = IDebtLockerFactory(dlFactory).newLocker(loan);
            debtLockers[loan][dlFactory] = debtLocker;
            _debtLocker = debtLocker;
        }
        
        principalOut = principalOut.add(amt);
        // Fund loan.
        ILiquidityLocker(liquidityLocker).fundLoan(loan, _debtLocker, amt);
        
        emit LoanFunded(loan, _debtLocker, amt);
        emit BalanceUpdated(liquidityLocker, address(liquidityAsset), _balanceOfLiquidityLocker());
    }

    /**
        @dev Claim available funds for loan through specified debt locker factory.
        @param  loan      Address of the loan to claim from.
        @param  dlFactory The debt locker factory (always maps to a single debt locker).
        @return [0] = Total amount claimed.
                [1] = Interest portion claimed.
                [2] = Principal portion claimed.
                [3] = Fee portion claimed.
                [4] = Excess portion claimed.
                [5] = TODO: Liquidation portion claimed.
    */
    function claim(address loan, address dlFactory) public returns(uint[5] memory) { 
        
        uint[5] memory claimInfo = IDebtLocker(debtLockers[loan][dlFactory]).claim();

        uint256 poolDelegatePortion = claimInfo[1].mul(delegateFee).div(10000).add(claimInfo[3]);  // PD portion of interest plus fee
        uint256 stakeLockerPortion  = claimInfo[1].mul(stakingFee).div(10000);                     // SL portion of interest

        uint256 principalClaim = claimInfo[2].add(claimInfo[4]);  // Principal + excess
        uint256 interestClaim  = claimInfo[1].sub(claimInfo[1].mul(delegateFee).div(10000)).sub(stakeLockerPortion);  // Leftover interest

        // Subtract outstanding principal by principal claimed plus excess returned
        principalOut = principalOut.sub(principalClaim);

        // Accounts for rounding error in stakeLocker/poolDelegate/liquidityLocker interest split
        interestSum = interestSum.add(interestClaim);

        require(liquidityAsset.transfer(poolDelegate, poolDelegatePortion), "Pool:PD_CLAIM_TRANSFER");  // Transfer fee and portion of interest to pool delegate
        require(liquidityAsset.transfer(stakeLocker,  stakeLockerPortion),  "Pool:SL_CLAIM_TRANSFER");  // Transfer portion of interest to stakeLocker

        // Transfer remaining claim (remaining interest + principal + excess) to liquidityLocker
        // Dust will accrue in Pool, but this ensures that state variables are in sync with liquidityLocker balance updates
        // Not using balanceOf in case of external address transferring liquidityAsset directly into Pool
        // Ensures that internal accounting is exactly reflective of balance change
        require(liquidityAsset.transfer(liquidityLocker, principalClaim.add(interestClaim)), "Pool:LL_CLAIM_TRANSFER"); 

        // Update funds received for FDT StakeLocker tokens.
        IStakeLocker(stakeLocker).updateFundsReceived();
        
        // Update the `pointsPerShare` & funds received for FDT Pool tokens.
        updateFundsReceived();

        emit BalanceUpdated(liquidityLocker, address(liquidityAsset), _balanceOfLiquidityLocker());
        emit BalanceUpdated(stakeLocker,     address(liquidityAsset), liquidityAsset.balanceOf(stakeLocker));

        emit Claim(loan, claimInfo[1], principalClaim, claimInfo[3]);

        return claimInfo;
    }

    /**
        @dev Pool Delegate triggers deactivation, permanently shutting down the pool.
        @param confirmation Pool delegate must supply the number 86 for this function to deactivate, a simple confirmation.
    */
    function deactivate(uint confirmation) external isState(State.Finalized) isDelegate {
        require(confirmation == 86, "Pool:INVALID_CONFIRMATION");
        require(principalOut <= 100 * 10 ** liquidityAssetDecimals);
        poolState = State.Deactivated;
    }

    /** 
        @dev Calculate the amount of funds to deduct from total claimable amount based on how
             the effective length of time a user has been in a pool. This is a linear decrease
             until block.timestamp - depositDate[who] >= penaltyDelay, after which it returns 0.
        @param  amt Total claimable amount 
        @param  who Address of user claiming
        @return penalty Total penalty
    */
    function calcWithdrawPenalty(uint256 amt, address who) public returns (uint256 penalty) {
        uint256 dTime    = (block.timestamp.sub(depositDate[who])).mul(WAD);
        uint256 unlocked = dTime.div(penaltyDelay).mul(amt) / WAD;

        penalty = unlocked > amt ? 0 : amt - unlocked;
    }

    /**
        @dev Update the effective deposit date based on how much new capital has been added.
             If more capital is added, the depositDate moves closer to the current timestamp.
        @param  amt Total deposit amount
        @param  who Address of user depositing
    */
    function updateDepositDate(uint256 amt, address who) internal {
        if (depositDate[who] == 0) {
            depositDate[who] = block.timestamp;
        } else {
            uint256 depDate  = depositDate[who];
            uint256 coef     = (WAD.mul(amt)).div(balanceOf(who) + amt);
            depositDate[who] = (depDate.mul(WAD).add((block.timestamp.sub(depDate)).mul(coef))).div(WAD);  // depDate + (now - depDate) * coef
        }
    }

    /**
        @dev Set the amount of time required to recover 100% of claimable funds 
             (i.e. calcWithdrawPenalty = 0)
        @param _penaltyDelay Effective time needed in pool for user to be able to claim 100% of funds
    */
    function setPenaltyDelay(uint256 _penaltyDelay) public isDelegate {
        penaltyDelay = _penaltyDelay;
    }

    /**
        @dev Allowing delegate/pool manager to set the principal penalty.
        @param _newPrincipalPenalty New principal penalty percentage (in bips) that corresponds to withdrawal amount.
    */
    function setPrincipalPenalty(uint256 _newPrincipalPenalty) public isDelegate {
        principalPenalty = _newPrincipalPenalty;
        // TODO: Emit an event
    }

    /**
        @dev Convert liquidityAsset to WAD precision (10 ** 18)
        @param amt Effective time needed in pool for user to be able to claim 100% of funds
    */
    function _toWad(uint256 amt) internal view returns(uint256) {
        return amt.mul(WAD).div(10 ** liquidityAssetDecimals);
    }

    /**
        @dev Fetch the balance of this Pool's liquidity locker.
        @return Balance of liquidity locker.
    */
    function _balanceOfLiquidityLocker() internal view returns(uint256) {
        return liquidityAsset.balanceOf(liquidityLocker);
    } 

    /**
        @dev Withdraws all claimable interest from the `liquidityLocker` for a user using `interestSum` accounting.
    */
    function withdrawFunds() public override(FDT) {
        uint256 withdrawableFunds = _prepareWithdraw();

        require(
            ILiquidityLocker(liquidityLocker).transfer(msg.sender, withdrawableFunds),
            "FDT_ERC20Extension.withdrawFunds: TRANSFER_FAILED"
        );

        interestSum = interestSum.sub(withdrawableFunds);

        _updateFundsTokenBalance();
    }

    /**
        @dev Updates the current funds token balance and returns the difference of new and previous funds token balances.
        @return A int256 representing the difference of the new and previous funds token balance.
    */
    function _updateFundsTokenBalance() internal override returns (int256) {
        uint256 _prevFundsTokenBalance = fundsTokenBalance;

        fundsTokenBalance = interestSum;

        return int256(fundsTokenBalance).sub(int256(_prevFundsTokenBalance));
    }
}
