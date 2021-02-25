// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "./token/PoolFDT.sol";

import "./interfaces/IBPool.sol";
import "./interfaces/IDebtLocker.sol";
import "./interfaces/IDebtLockerFactory.sol";
import "./interfaces/IGlobals.sol";
import "./interfaces/ILiquidityLocker.sol";
import "./interfaces/ILiquidityLockerFactory.sol";
import "./interfaces/ILoan.sol";
import "./interfaces/ILoanFactory.sol";
import "./interfaces/IPoolFactory.sol";
import "./interfaces/IStakeLocker.sol";
import "./interfaces/IStakeLockerFactory.sol";

import "./library/CalcBPool.sol";

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title Pool is the core contract for liquidity pools.
contract Pool is PoolFDT {

    using SafeMath  for uint256;

    uint256 constant WAD = 10 ** 18;

    uint8 public constant DL_FACTORY = 1;   // Factory type of `DebtLockerFactory`.

    IERC20  public immutable liquidityAsset;   // The asset deposited by lenders into the LiquidityLocker, for funding loans.

    address public immutable poolDelegate;     // The pool delegate, who maintains full authority over this Pool.
    address public immutable liquidityLocker;  // The LiquidityLocker owned by this contract.
    address public immutable stakeAsset;       // The asset deposited by stakers into the StakeLocker, for liquidation during default events.
    address public immutable stakeLocker;      // Address of the StakeLocker, escrowing the staked asset.
    address public immutable slFactory;        // Address of the StakeLocker factory.
    address public immutable superFactory;     // The factory that deployed this Loan.

    uint256 private immutable liquidityAssetDecimals;  // decimals() precision for the liquidityAsset.

    // Universal accounting law: fdtTotalSupply = liquidityLockerBal + principalOut - interestSum + bptShortfall
    //        liquidityLockerBal + principalOut = fdtTotalSupply + interestSum - bptShortfall

    uint256 public principalOut;      // Sum of all outstanding principal on loans
    uint256 public stakingFee;        // The fee for stakers (in basis points).
    uint256 public delegateFee;       // The fee for delegates (in basis points).
    uint256 public principalPenalty;  // Max penalty on principal in bips on early withdrawal.
    uint256 public penaltyDelay;      // Time until total interest is available after a deposit, in seconds.
    uint256 public liquidityCap;      // Amount of liquidity tokens accepted by the pool.
    uint256 public lockupPeriod;      // Unix timestamp until the withdrawal is not allowed.

    enum State { Initialized, Finalized, Deactivated }
    State public poolState;  // The current state of this pool.

    mapping(address => uint256)                     public depositDate;  // Used for interest penalty calculation
    mapping(address => mapping(address => address)) public debtLockers;  // loans[LOAN_VAULT][LOCKER_FACTORY] = DebtLocker
    mapping(address => bool)                        public admins;       // Admin addresses who have permission to do certain operations in case of disaster mgt.

    event       LoanFunded(address indexed loan, address debtLocker, uint256 amountFunded);
    event            Claim(address indexed loan, uint256 interest, uint256 principal, uint256 fee);
    event   BalanceUpdated(address indexed who,  address token, uint256 balance);
    event  LiquidityCapSet(uint256 newLiquidityCap);
    event PoolStateChanged(State state);
    event  DefaultSuffered(
        address loan, 
        uint256 defaultSuffered, 
        uint256 bptsBurned, 
        uint256 bptsReturned,
        uint256 liquidityAssetRecoveredFromBurn
    );

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
    ) PoolFDT(name, symbol) public {
        require(_globals(msg.sender).isValidLoanAsset(_liquidityAsset), "Pool:INVALID_LIQ_ASSET");
        require(_liquidityCap   != uint256(0),                          "Pool:INVALID_CAP");

        // NOTE: Max length of this array would be 8, as thats the limit of assets in a balancer pool
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
        lockupPeriod     = 90 days;

        emit PoolStateChanged(poolState);
    }

    /**
        @dev Deploys and assigns a StakeLocker for this Pool (only used once in constructor).
        @param _stakeAsset     Address of the asset used for staking.
        @param _slFactory      Address of the StakeLocker factory used for instantiation.
        @param _liquidityAsset Address of the liquidity asset, required when burning _stakeAsset.
        @param globals         IGlobals for Maple Globals contract.
    */
    function createStakeLocker(address _stakeAsset, address _slFactory, address _liquidityAsset, IGlobals globals) private returns (address) {
        require(IBPool(_stakeAsset).isBound(globals.mpl()) && IBPool(_stakeAsset).isFinalized(), "Pool:INVALID_BALANCER_POOL");
        return IStakeLockerFactory(_slFactory).newLocker(_stakeAsset, _liquidityAsset);
    }

    /**
        @dev Finalize the pool, enabling deposits. Checks poolDelegate amount deposited to StakeLocker.
    */
    function finalize() external {
        _whenProtocolNotPaused();
        _isValidState(State.Initialized);
        _isValidDelegate();
        (,, bool stakePresent,,) = getInitialStakeRequirements();
        require(stakePresent, "Pool:INSUFFICIENT_STAKE");
        poolState = State.Finalized;
        emit PoolStateChanged(poolState);
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
        return CalcBPool.getInitialStakeRequirements(_globals(superFactory), stakeAsset, address(liquidityAsset), poolDelegate, stakeLocker);
    }

    /**
        @dev Calculates BPTs required if burning BPTs for pair, given supplied tokenAmountOutRequired.
        @param  bpool              Balancer pool that issues the BPTs.
        @param  pair               Swap out asset (e.g. USDC) to receive when burning BPTs.
        @param  staker             Address that deposited BPTs to stakeLocker.
        @param  _stakeLocker       Escrows BPTs deposited by staker.
        @param  pairAmountRequired Amount of pair tokens out required.
        @return [0] = poolAmountIn required
                [1] = poolAmountIn currently staked.
    */
    function getPoolSharesRequired(
        address bpool,
        address pair,
        address staker,
        address _stakeLocker,
        uint256 pairAmountRequired
    ) external view returns (uint256, uint256) {
        return CalcBPool.getPoolSharesRequired(bpool, pair, staker, _stakeLocker, pairAmountRequired);
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
        @dev Set `liquidityCap`, Only allowed by the pool delegate or the admin.
        @param newLiquidityCap New liquidity cap value. 
    */
    function setLiquidityCap(uint256 newLiquidityCap) external {
        _whenProtocolNotPaused();
        _isValidDelegateOrAdmin();
        liquidityCap = newLiquidityCap;
        emit LiquidityCapSet(newLiquidityCap);
    }

    /**
        @dev Liquidity providers can deposit LiqudityAsset into the LiquidityLocker, minting FDTs.
        @param amt The amount of LiquidityAsset to deposit, in wei.
    */
    function deposit(uint256 amt) external {
        _whenProtocolNotPaused();
        _isValidState(State.Finalized);
        require(isDepositAllowed(amt), "Pool:LIQUIDITY_CAP_HIT");
        require(liquidityAsset.transferFrom(msg.sender, liquidityLocker, amt), "Pool:DEPOSIT_TRANSFER_FROM");
        uint256 wad = _toWad(amt);

        updateDepositDate(wad, msg.sender);
        _mint(msg.sender, wad);
        _emitBalanceUpdatedEvent();
    }

    /**
        @dev Liquidity providers can withdraw LiqudityAsset from the LiquidityLocker, burning FDTs.
        @param amt The amount of LiquidityAsset to withdraw.
    */
    function withdraw(uint256 amt) external {
        _whenProtocolNotPaused();
        uint256 wad    = _toWad(amt);
        uint256 fdtAmt = totalSupply() == wad && amt > 0 ? wad - 1 : wad;  // If last withdraw, subtract 1 wei to maintain FDT accounting
        require(balanceOf(msg.sender) >= fdtAmt, "Pool:USER_BAL_LT_AMT");
        require(depositDate[msg.sender].add(lockupPeriod) <= block.timestamp, "Pool:FUNDS_LOCKED");

        uint256 allocatedInterest = withdrawableFundsOf(msg.sender);                                     // Calculated interest.
        uint256 recognizedLosses  = recognizeableLossesOf(msg.sender);                                   // Calculated losses
        uint256 priPenalty        = principalPenalty.mul(amt).div(10000);                                // Calculate flat principal penalty.
        uint256 totPenalty        = calcWithdrawPenalty(allocatedInterest.add(priPenalty), msg.sender);  // Get total penalty, however it may be calculated.

        // Amount that is due after penalties and realized losses are accounted for. 
        // Total penalty is distributed to other LPs as interest, recognizedLosses are absorbed by the LP.
        uint256 due = amt.sub(totPenalty).sub(recognizedLosses);

        _burn(msg.sender, fdtAmt);  // Burn the corresponding FDT balance.
        recognizeLosses();          // Update loss accounting for LP,   decrement `bptShortfall`
        withdrawFunds();            // Transfer full entitled interest, decrement `interestSum`

        // Transfer amt - totPenalty - recognizedLosses
        require(ILiquidityLocker(liquidityLocker).transfer(msg.sender, due), "Pool::WITHDRAW_TRANSFER");

        interestSum  = interestSum.add(totPenalty);  // Update the `interestSum` with the penalty amount.
        updateFundsReceived();                       // Update the `pointsPerShare` using this as fundsTokenBalance is incremented by `totPenalty`.

        _emitBalanceUpdatedEvent();
    }

    /**
        @dev Fund a loan for amt, utilize the supplied dlFactory for debt lockers.
        @param  loan      Address of the loan to fund.
        @param  dlFactory The debt locker factory to utilize.
        @param  amt       Amount to fund the loan.
    */
    function fundLoan(address loan, address dlFactory, uint256 amt) external {
        _whenProtocolNotPaused();
        _isValidState(State.Finalized);
        _isValidDelegate();
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
        
        principalOut = principalOut.add(amt);
        // Fund loan.
        ILiquidityLocker(liquidityLocker).fundLoan(loan, _debtLocker, amt);
        
        emit LoanFunded(loan, _debtLocker, amt);
        _emitBalanceUpdatedEvent();
    }

    // Helper function for claim() if a default has occurred.
    function _handleDefault(address loan, uint256 defaultSuffered) internal {

        // Check liquidityAsset swapOut value of StakeLocker coverage
        uint256 availableSwapOut = CalcBPool.getSwapOutValueLocker(stakeAsset, address(liquidityAsset), stakeLocker);
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
        uint256 bptsBurned = IBPool(stakeAsset).exitswapExternAmountOut(
                                address(liquidityAsset), 
                                availableSwapOut >= defaultSuffered ? defaultSuffered : availableSwapOut, 
                                uint256(-1)
                            );

        // Return remaining BPTs to stakeLocker.
        uint256 bptsReturned = IBPool(stakeAsset).balanceOf(address(this));
        IBPool(stakeAsset).transfer(stakeLocker, bptsReturned);

        uint256 liquidityAssetRecoveredFromBurn = liquidityAsset.balanceOf(address(this)).sub(preBurnBalance);

        // Handle shortfall in StakeLocker, liquidity providers suffer a loss
        if (defaultSuffered > liquidityAssetRecoveredFromBurn) {
            bptShortfall = bptShortfall.add(defaultSuffered - liquidityAssetRecoveredFromBurn);
            updateLossesReceived();
        }

        // Transfer USDC to liquidityLocker.
        liquidityAsset.transfer(liquidityLocker, liquidityAssetRecoveredFromBurn);

        principalOut = principalOut.sub(defaultSuffered);

        emit DefaultSuffered(
            loan,                            // Which loan this defaultSuffered is from
            defaultSuffered,                 // Total default suffered from loan by pool after liquidation
            bptsBurned,                      // Amount of BPTs burned from stakeLocker
            bptsReturned,                    // Remaining BPTs in stakeLocker post-burn                      
            liquidityAssetRecoveredFromBurn  // Amount of liquidityAsset recovered from burning BPTs
        );
    }

    /**
        @dev Claim available funds for loan through specified debt locker factory.
        @param  loan      Address of the loan to claim from.
        @param  dlFactory The debt locker factory (always maps to a single debt locker).
        @return [0] = Total amount claimed
                [1] = Interest  portion claimed
                [2] = Principal portion claimed
                [3] = Fee       portion claimed
                [4] = Excess    portion claimed
                [5] = Recovered portion claimed (from liquidations)
                [6] = Default suffered
    */
    function claim(address loan, address dlFactory) external returns(uint256[7] memory) { 
        _whenProtocolNotPaused();
        uint256[7] memory claimInfo = IDebtLocker(debtLockers[loan][dlFactory]).claim();

        uint256 poolDelegatePortion = claimInfo[1].mul(delegateFee).div(10000).add(claimInfo[3]);  // PD portion of interest plus fee
        uint256 stakeLockerPortion  = claimInfo[1].mul(stakingFee).div(10000);                     // SL portion of interest

        uint256 principalClaim = claimInfo[2].add(claimInfo[4]).add(claimInfo[5]);                                    // Principal + excess + amountRecovered
        uint256 interestClaim  = claimInfo[1].sub(claimInfo[1].mul(delegateFee).div(10000)).sub(stakeLockerPortion);  // Leftover interest

        // Subtract outstanding principal by principal claimed plus excess returned
        principalOut = principalOut.sub(principalClaim);

        // Accounts for rounding error in stakeLocker/poolDelegate/liquidityLocker interest split
        interestSum = interestSum.add(interestClaim);

        _transferLiquidityAsset(poolDelegate, poolDelegatePortion);  // Transfer fee and portion of interest to pool delegate.
        _transferLiquidityAsset(stakeLocker, stakeLockerPortion);    // Transfer portion of interest to stakeLocker

        // Transfer remaining claim (remaining interest + principal + excess + recovered) to liquidityLocker
        // Dust will accrue in Pool, but this ensures that state variables are in sync with liquidityLocker balance updates
        // Not using balanceOf in case of external address transferring liquidityAsset directly into Pool
        // Ensures that internal accounting is exactly reflective of balance change
        _transferLiquidityAsset(liquidityLocker, principalClaim.add(interestClaim)); 
        
        // Handle default if defaultSuffered > 0
        if (claimInfo[6] > 0) _handleDefault(loan, claimInfo[6]);

        // Update funds received for FDT StakeLocker tokens.
        IStakeLocker(stakeLocker).updateFundsReceived();
        
        // Update the `pointsPerShare` & funds received for FDT Pool tokens.
        updateFundsReceived();

        _emitBalanceUpdatedEvent();
        emit BalanceUpdated(stakeLocker, address(liquidityAsset), liquidityAsset.balanceOf(stakeLocker));

        emit Claim(loan, claimInfo[1], principalClaim, claimInfo[3]);

        return claimInfo;
    }

    /**
        @dev Pool Delegate triggers deactivation, permanently shutting down the pool.
        @param confirmation Pool delegate must supply the number 86 for this function to deactivate, a simple confirmation.
    */
    function deactivate(uint confirmation) external {
        _whenProtocolNotPaused();
        _isValidState(State.Finalized);
        _isValidDelegate();
        require(confirmation == 86, "Pool:INVALID_CONFIRMATION");  // TODO: Remove this
        require(principalOut <= 100 * 10 ** liquidityAssetDecimals);
        poolState = State.Deactivated;
        emit PoolStateChanged(poolState);
    }

    /** 
        @dev Calculate the amount of funds to deduct from total claimable amount based on how
             the effective length of time a user has been in a pool. This is a linear decrease
             until block.timestamp - depositDate[who] >= penaltyDelay, after which it returns 0.
        @param  amt Total claimable amount 
        @param  who Address of user claiming
        @return penalty Total penalty
    */
    function calcWithdrawPenalty(uint256 amt, address who) public view returns (uint256 penalty) {
        if (lockupPeriod < penaltyDelay) {
            uint256 dTime    = block.timestamp.sub(depositDate[who]);
            uint256 unlocked = dTime.mul(amt).div(penaltyDelay);

            penalty = unlocked > amt ? 0 : amt - unlocked;
        }
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
    function setPenaltyDelay(uint256 _penaltyDelay) external {
        _whenProtocolNotPaused();
        _isValidDelegate();
        penaltyDelay = _penaltyDelay;
    }

    /**
        @dev Allowing delegate/pool manager to set the principal penalty.
        @param _newPrincipalPenalty New principal penalty percentage (in bips) that corresponds to withdrawal amount.
    */
    function setPrincipalPenalty(uint256 _newPrincipalPenalty) external {
        _whenProtocolNotPaused();
        _isValidDelegate();
        principalPenalty = _newPrincipalPenalty;
    }

    /**
        @dev Allowing delegate/pool manager to set the lockup period.
        @param _newLockupPeriod New lockup period used to restrict the withdrawals.
     */
    function setLockupPeriod(uint256 _newLockupPeriod) external {
        _whenProtocolNotPaused();
        _isValidDelegate();
        lockupPeriod = _newLockupPeriod;
    }

    /**
        @dev Update user status on StakeLocker whitelist.
        @param user   The address to set status for.
        @param status The status of user on whitelist.
    */
    function setWhitelistStakeLocker(address user, bool status) external {
        _whenProtocolNotPaused();
        _isValidDelegate();
        IStakeLocker(stakeLocker).setWhitelist(user, status);
    }

    /**
        @dev View claimable balance from LiqudityLocker (reflecting deposit + gain/loss).
        @param lp Liquidity Provider to check claimableFunds for 
        @return [0] = Total amount claimable.
                [1] = Principal amount claimable.
                [2] = Interest amount claimable.
    */
    function claimableFunds(address lp) public view returns(uint256, uint256, uint256) {

        // Deposit is still within lockupPeriod, user has 0 claimableFunds under this condition.
        if (depositDate[lp].add(lockupPeriod) > block.timestamp) {
            return (withdrawableFundsOf(lp), 0, withdrawableFundsOf(lp)); 
        }
        else {
            uint256 userBalance    = _fromWad(balanceOf(lp));
            uint256 interestEarned = withdrawableFundsOf(lp);                       // Calculate interest earned
            uint256 firstPenalty   = principalPenalty.mul(userBalance).div(10000);  // Calculate flat principal penalty
            uint256 totalPenalty   = calcWithdrawPenalty(                           // Calculate total penalty
                                        interestEarned.add(firstPenalty),
                                        lp
                                    );
            return (
                userBalance.sub(totalPenalty).add(interestEarned), 
                userBalance.sub(totalPenalty), 
                interestEarned
            );
        }
    }

    /**
        @dev Liquidate the loan. Pool delegate could liquidate a loan only when
             loan completes its grace period.
             This will increase the `pointsPerShare` contribution of the debt lockers (i.e holders of loan FDT).
             Pool delegate can claim its proportion of fund using the `claim()` function.
        @param loan Address of the loan contract that is need to be liquidated.
        @param dlFactory Address of the debt locker factory that is used to generate the corresponding debt locker.
     */
    function triggerDefault(address loan, address dlFactory) external {
        _whenProtocolNotPaused();
        _isValidDelegate();
        IDebtLocker(debtLockers[loan][dlFactory]).triggerDefault();
    }

    /**
        @dev Convert liquidityAsset to WAD precision (10 ** 18)
        @param amt Effective time needed in pool for user to be able to claim 100% of funds
    */
    function _toWad(uint256 amt) internal view returns(uint256) {
        return amt.mul(WAD).div(10 ** liquidityAssetDecimals);
    }

    /**
        @dev Convert liquidityAsset to WAD precision (10 ** 18)
        @param amt Effective time needed in pool for user to be able to claim 100% of funds
    */
    function _fromWad(uint256 amt) internal view returns(uint256) {
        return amt.mul(10 ** liquidityAssetDecimals).div(WAD);
    }

    /**
        @dev Fetch the balance of this Pool's liquidity locker.
        @return Balance of liquidity locker.
    */
    function _balanceOfLiquidityLocker() internal view returns(uint256) {
        return liquidityAsset.balanceOf(liquidityLocker);
    }

    /**
        @dev Transfers liquidity asset from address(this) to given `to` address.
        @param to Whom liquidity asset needs to transferred.
        @param value Amount of liquidity asset that gets transferred.
    */
    function _transferLiquidityAsset(address to, uint256 value) internal {
        require(liquidityAsset.transfer(to, value), "Pool:CLAIM_TRANSFER");
    } 

    function _isValidState(State _state) internal view {
        require(poolState == _state, "Pool:STATE_CHECK");
    }

    function _isValidDelegate() internal view {
        require(msg.sender == poolDelegate, "Pool:INVALID_DELEGATE");
    }

    function _globals(address poolFactory) internal view returns (IGlobals) {
        return IGlobals(ILoanFactory(poolFactory).globals());
    }

    function _emitBalanceUpdatedEvent() internal {
        emit BalanceUpdated(liquidityLocker, address(liquidityAsset), _balanceOfLiquidityLocker());
    }

    /**
        @dev Withdraws all claimable interest from the `liquidityLocker` for a user using `interestSum` accounting.
    */
    function withdrawFunds() public override {
        _whenProtocolNotPaused();
        uint256 withdrawableFunds = _prepareWithdraw();

        require(
            ILiquidityLocker(liquidityLocker).transfer(msg.sender, withdrawableFunds),
            "FDT_ERC20:TRANSFER_FAILED"
        );

        interestSum = interestSum.sub(withdrawableFunds);

        _updateFundsTokenBalance();
    }

    /**
      @dev Set admin
      @param newAdmin new admin address.
      @param allowed Status of an admin.
     */
    function setAdmin(address newAdmin, bool allowed) external {
        _whenProtocolNotPaused();
        _isValidDelegate();
        admins[newAdmin] = allowed;
    }

    function _isValidDelegateOrAdmin() internal {
        require(msg.sender == poolDelegate || admins[msg.sender], "Pool:UNAUTHORIZED");
    }

    function _whenProtocolNotPaused() internal {
        require(!_globals(superFactory).protocolPaused(), "Pool:PROTOCOL_PAUSED");
    }

    function _whenProtocolNotPaused() internal {
        require(!_globals(superFactory).protocolPaused(), "Pool:PROTOCOL_PAUSED");
    }
}
