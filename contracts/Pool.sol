// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

import "./token/PoolFDT.sol";

import "./interfaces/IBPool.sol";
import "./interfaces/IDebtLocker.sol";
import "./interfaces/IGlobals.sol";
import "./interfaces/ILiquidityLocker.sol";
import "./interfaces/ILiquidityLockerFactory.sol";
import "./interfaces/ILoan.sol";
import "./interfaces/ILoanFactory.sol";
import "./interfaces/IPoolFactory.sol";
import "./interfaces/IStakeLocker.sol";
import "./interfaces/IStakeLockerFactory.sol";

import "./library/PoolLib.sol";

import "lib/openzeppelin-contracts/contracts/token/ERC20/SafeERC20.sol";

/// @title Pool maintains all accounting and functionality related to Pools.
contract Pool is PoolFDT {

    using SafeMath  for uint256;
    using SafeERC20 for IERC20;

    uint256 constant WAD = 10 ** 18;

    uint8 public constant DL_FACTORY = 1;  // Factory type of `DebtLockerFactory`

    IERC20  public immutable liquidityAsset;   // The asset deposited by lenders into the LiquidityLocker, for funding Loans

    address public immutable poolDelegate;     // Pool Delegate address, maintains full authority over the Pool
    address public immutable liquidityLocker;  // The LiquidityLocker owned by this contract
    address public immutable stakeAsset;       // The asset deposited by stakers into the StakeLocker (BPTs), for liquidation during default events
    address public immutable stakeLocker;      // Address of the StakeLocker, escrowing stakeAsset
    address public immutable slFactory;        // Address of the StakeLocker factory
    address public immutable superFactory;     // The factory that deployed this Loan

    uint256 private immutable liquidityAssetDecimals;  // decimals() precision for the liquidityAsset

    // Universal accounting law: fdtTotalSupply = liquidityLockerBal + principalOut - interestSum + bptShortfall
    //        liquidityLockerBal + principalOut = fdtTotalSupply + interestSum - bptShortfall

    uint256 public principalOut;      // Sum of all outstanding principal on Loans
    uint256 public stakingFee;        // Fee for stakers   (in basis points)
    uint256 public delegateFee;       // Fee for delegates (in basis points)
    uint256 public principalPenalty;  // Max penalty on principal in basis points on early withdrawal
    uint256 public penaltyDelay;      // Time until total interest and principal is available after a deposit, in seconds
    uint256 public liquidityCap;      // Amount of liquidity tokens accepted by the Pool
    uint256 public lockupPeriod;      // Unix timestamp during which withdrawal is not allowed

    enum State { Initialized, Finalized, Deactivated }
    State public poolState;  // The current state of this pool

    mapping(address => uint256)                     public depositDate;  // Used for withdraw penalty calculation
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
        @param  _poolDelegate   Address that has manager privileges for the Pool
        @param  _liquidityAsset Asset escrowed in LiquidityLocker
        @param  _stakeAsset     Asset escrowed in StakeLocker
        @param  _slFactory      Factory used to instantiate StakeLocker
        @param  _llFactory      Factory used to instantiate LiquidityLocker
        @param  _stakingFee     Fee that stakers earn on interest, in basis points
        @param  _delegateFee    Fee that _poolDelegate earns on interest, in basis points
        @param  _liquidityCap   Max amount of liquidityAsset accepted by the Pool
        @param  name            Name of Pool token
        @param  symbol          Symbol of Pool token
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
        require(_liquidityCap != uint256(0),                            "Pool:INVALID_CAP");

        // NOTE: Max length of this array would be 8, as thats the limit of assets in a balancer pool
        address[] memory tokens = IBPool(_stakeAsset).getFinalTokens();

        uint256  i = 0;
        bool valid = false;

        // Check that one of the assets in balancer pool is liquidityAsset
        while(i < tokens.length && !valid) { valid = tokens[i] == _liquidityAsset; i++; }  

        require(valid, "Pool:INVALID_STAKING_POOL");

        // Assign variables relating to liquidityAsset
        liquidityAsset         = IERC20(_liquidityAsset);
        liquidityAssetDecimals = ERC20(_liquidityAsset).decimals();

        // Assign state variables
        stakeAsset   = _stakeAsset;
        slFactory    = _slFactory;
        poolDelegate = _poolDelegate;
        stakingFee   = _stakingFee;
        delegateFee  = _delegateFee;
        superFactory = msg.sender;
        liquidityCap = _liquidityCap;

        // Initialize the LiquidityLocker and StakeLocker
        stakeLocker     = createStakeLocker(_stakeAsset, _slFactory, _liquidityAsset, _globals(msg.sender));
        liquidityLocker = address(ILiquidityLockerFactory(_llFactory).newLocker(_liquidityAsset));

        // Withdrawal penalty default settings
        principalPenalty = 500;
        penaltyDelay     = 30 days;
        lockupPeriod     = 90 days;

        emit PoolStateChanged(poolState);
    }

    /**
        @dev Deploys and assigns a StakeLocker for this Pool (only used once in constructor).
        @param _stakeAsset     Address of the asset used for staking
        @param _slFactory      Address of the StakeLocker factory used for instantiation
        @param _liquidityAsset Address of the liquidity asset, required when burning _stakeAsset
        @param globals         IGlobals for Maple Globals contract
    */
    function createStakeLocker(address _stakeAsset, address _slFactory, address _liquidityAsset, IGlobals globals) private returns (address) {
        require(IBPool(_stakeAsset).isBound(globals.mpl()) && IBPool(_stakeAsset).isFinalized(), "Pool:INVALID_BALANCER_POOL");
        return IStakeLockerFactory(_slFactory).newLocker(_stakeAsset, _liquidityAsset);
    }

    /**
        @dev Finalize the Pool, enabling deposits. Checks Pool Delegate amount deposited to StakeLocker.
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
                [1] = Present amount of liquidityAsset coverage from Pool Delegate stake
                [2] = If enough stake is present from Pool Delegate for finalization
                [3] = Staked BPTs required for minimum liquidityAsset coverage
                [4] = Current staked BPTs
    */
    function getInitialStakeRequirements() public view returns (uint256, uint256, bool, uint256, uint256) {
        return PoolLib.getInitialStakeRequirements(_globals(superFactory), stakeAsset, address(liquidityAsset), poolDelegate, stakeLocker);
    }

    /**
        @dev Calculates BPTs required if burning BPTs for liquidityAsset, given supplied tokenAmountOutRequired.
        @param  _bPool                        Balancer pool that issues the BPTs
        @param  _liquidityAsset              Swap out asset (e.g. USDC) to receive when burning BPTs
        @param  _staker                       Address that deposited BPTs to stakeLocker
        @param  _stakeLocker                 Escrows BPTs deposited by staker
        @param  _liquidityAssetAmountRequired Amount of liquidityAsset required to recover
        @return [0] = poolAmountIn required
                [1] = poolAmountIn currently staked
    */
    function getPoolSharesRequired(
        address _bPool,
        address _liquidityAsset,
        address _staker,
        address _stakeLocker,
        uint256 _liquidityAssetAmountRequired
    ) public view returns (uint256, uint256) {
        return PoolLib.getPoolSharesRequired(_bPool, _liquidityAsset, _staker, _stakeLocker, _liquidityAssetAmountRequired);
    }

    /**
        @dev Check whether the given `depositAmt` is acceptable based on current liquidityCap.
        @param depositAmt Amount of tokens (i.e loanAsset type) user is trying to deposit
    */
    function isDepositAllowed(uint256 depositAmt) public view returns(bool) {
        uint256 totalDeposits = _balanceOfLiquidityLocker().add(principalOut);
        return totalDeposits.add(depositAmt) <= liquidityCap;
    }

    /**
        @dev Set `liquidityCap`, Only allowed by the Pool Delegate or the admin.
        @param newLiquidityCap New liquidityCap value
    */
    function setLiquidityCap(uint256 newLiquidityCap) external {
        _whenProtocolNotPaused();
        _isValidDelegateOrAdmin();
        liquidityCap = newLiquidityCap;
        emit LiquidityCapSet(newLiquidityCap);
    }

    /**
        @dev Liquidity providers can deposit liquidityAsset into the LiquidityLocker, minting FDTs.
        @param amt Amount of liquidityAsset to deposit
    */
    function deposit(uint256 amt) external {
        _whenProtocolNotPaused();
        _isValidState(State.Finalized);
        require(isDepositAllowed(amt), "Pool:LIQUIDITY_CAP_HIT");
        require(liquidityAsset.transferFrom(msg.sender, liquidityLocker, amt), "Pool:DEPOSIT_TRANSFER_FROM");
        uint256 wad = _toWad(amt);

        PoolLib.updateDepositDate(depositDate, balanceOf(msg.sender), wad, msg.sender);
        _mint(msg.sender, wad);
        _emitBalanceUpdatedEvent();
    }

    /**
        @dev Liquidity providers can withdraw liquidityAsset from the LiquidityLocker, burning FDTs.
        @param amt Amount of liquidityAsset to withdraw
    */
    function withdraw(uint256 amt) external {
        _whenProtocolNotPaused();
        uint256 wad    = _toWad(amt);
        uint256 fdtAmt = totalSupply() == wad && amt > 0 ? wad - 1 : wad;  // If last withdraw, subtract 1 wei to maintain FDT accounting
        require(balanceOf(msg.sender) >= fdtAmt, "Pool:USER_BAL_LT_AMT");
        require(depositDate[msg.sender].add(lockupPeriod) <= block.timestamp, "Pool:FUNDS_LOCKED");

        uint256 allocatedInterest = withdrawableFundsOf(msg.sender);                                     // FDT accounting interest
        uint256 recognizedLosses  = recognizableLossesOf(msg.sender);                                    // FDT accounting losses
        uint256 priPenalty        = principalPenalty.mul(amt).div(10000);                                // Calculate flat principal penalty
        uint256 totPenalty        = calcWithdrawPenalty(allocatedInterest.add(priPenalty), msg.sender);  // Calculate total penalty

        // Amount that is due after penalties and realized losses are accounted for. 
        // Total penalty is distributed to other LPs as interest, recognizedLosses are absorbed by the LP.
        uint256 due = amt.sub(totPenalty).sub(recognizedLosses);

        _burn(msg.sender, fdtAmt);  // Burn the corresponding FDT balance
        recognizeLosses();          // Update loss accounting for LP,   decrement `bptShortfall`
        withdrawFunds();            // Transfer full entitled interest, decrement `interestSum`

        interestSum = interestSum.add(totPenalty);  // Update the `interestSum` with the penalty amount
        updateFundsReceived();                      // Update the `pointsPerShare` using this as fundsTokenBalance is incremented by `totPenalty`

        // Transfer amt - totPenalty - recognizedLosses
        ILiquidityLocker(liquidityLocker).transfer(msg.sender, due);

        _emitBalanceUpdatedEvent();
    }

    /**
        @dev Fund a loan for amt, utilize the supplied dlFactory for debt lockers.
        @param  loan      Address of the loan to fund
        @param  dlFactory The DebtLockerFactory to utilize
        @param  amt       Amount to fund the loan
    */
    function fundLoan(address loan, address dlFactory, uint256 amt) external {
        _whenProtocolNotPaused();
        _isValidState(State.Finalized);
        _isValidDelegate();
        principalOut = principalOut.add(amt);
        PoolLib.fundLoan(debtLockers, superFactory, liquidityLocker, loan, dlFactory, amt);
        _emitBalanceUpdatedEvent();
    }

    /**
        @dev Helper function if a claim has been made and there is a non-zero defaultSuffered amount.
        @param loan            Address of loan that has defaulted
        @param defaultSuffered Losses suffered from default after liquidation
    */
    function _handleDefault(address loan, uint256 defaultSuffered) internal {

        (uint256 bptsBurned, uint256 bptsReturned, uint256 liquidityAssetRecoveredFromBurn) = PoolLib.handleDefault(liquidityAsset, stakeLocker, stakeAsset, loan, defaultSuffered);

        IStakeLocker(stakeLocker).updateLosses(bptsBurned);  // Update StakeLocker FDT loss accounting for BPTs

        // Handle shortfall in StakeLocker, updated LiquidityLocker FDT loss accounting for liquidityAsset
        if (defaultSuffered > liquidityAssetRecoveredFromBurn) {
            bptShortfall = bptShortfall.add(defaultSuffered - liquidityAssetRecoveredFromBurn);
            updateLossesReceived();
        }

        // Transfer USDC to liquidityLocker
        liquidityAsset.safeTransfer(liquidityLocker, liquidityAssetRecoveredFromBurn);

        principalOut = principalOut.sub(defaultSuffered);  // Subtract rest of Loan's principal from principalOut

        emit DefaultSuffered(
            loan,                            // Which loan defaultSuffered is from
            defaultSuffered,                 // Total default suffered from loan by Pool after liquidation
            bptsBurned,                      // Amount of BPTs burned from stakeLocker
            bptsReturned,                    // Remaining BPTs in stakeLocker post-burn                      
            liquidityAssetRecoveredFromBurn  // Amount of liquidityAsset recovered from burning BPTs
        );
    }

    /**
        @dev Claim available funds for loan through specified DebtLockerFactory.
        @param  loan      Address of the loan to claim from
        @param  dlFactory The DebtLockerFactory (always maps to a single debt locker)
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

        (uint256 poolDelegatePortion, uint256 stakeLockerPortion, uint256 principalClaim, uint256 interestClaim) = PoolLib.calculateClaimAndPortions(claimInfo, delegateFee, stakingFee);

        // Subtract outstanding principal by principal claimed plus excess returned
        principalOut = principalOut.sub(principalClaim);

        // Accounts for rounding error in stakeLocker/poolDelegate/liquidityLocker interest split
        interestSum = interestSum.add(interestClaim);

        _transferLiquidityAsset(poolDelegate, poolDelegatePortion);  // Transfer fee and portion of interest to pool delegate
        _transferLiquidityAsset(stakeLocker, stakeLockerPortion);    // Transfer portion of interest to stakeLocker

        // Transfer remaining claim (remaining interest + principal + excess + recovered) to liquidityLocker
        // Dust will accrue in Pool, but this ensures that state variables are in sync with liquidityLocker balance updates
        // Not using balanceOf in case of external address transferring liquidityAsset directly into Pool
        // Ensures that internal accounting is exactly reflective of balance change.
        _transferLiquidityAsset(liquidityLocker, principalClaim.add(interestClaim)); 
        
        // Handle default if defaultSuffered > 0
        if (claimInfo[6] > 0) _handleDefault(loan, claimInfo[6]);

        // Update funds received for StakeLockerFDTs
        IStakeLocker(stakeLocker).updateFundsReceived();
        
        // Update funds received for PoolFDTs
        updateFundsReceived();

        _emitBalanceUpdatedEvent();
        emit BalanceUpdated(stakeLocker, address(liquidityAsset), liquidityAsset.balanceOf(stakeLocker));

        emit Claim(loan, claimInfo[1], principalClaim, claimInfo[3]);

        return claimInfo;
    }

    /**
        @dev Pool Delegate triggers deactivation, permanently shutting down the pool. Must have less that 100 units of liquidityAsset principalOut.
        @param confirmation Pool delegate must supply the number 86 for this function to deactivate, a simple confirmation.
    */
    // TODO: Ask auditors about standard for confirmations
    function deactivate(uint confirmation) external {
        _whenProtocolNotPaused();
        _isValidState(State.Finalized);
        _isValidDelegate();
        require(confirmation == 86, "Pool:INVALID_CONFIRMATION");
        require(principalOut <= 100 * 10 ** liquidityAssetDecimals);  // TODO: Discuss with auditors what best option is here (100 WBTC is non-negligible, USDC is)
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
        return PoolLib.calcWithdrawPenalty(lockupPeriod, penaltyDelay, amt, depositDate[who]);
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
        @dev Set the principal penalty. Only Pool Delegate can call this function.
        @param _newPrincipalPenalty New principal penalty percentage (in basis points) that corresponds to withdrawal amount
    */
    function setPrincipalPenalty(uint256 _newPrincipalPenalty) external {
        _whenProtocolNotPaused();
        _isValidDelegate();
        principalPenalty = _newPrincipalPenalty;
    }

    /**
        @dev Set the lockup period. Only Pool Delegate can call this function.
        @param _newLockupPeriod New lockup period used to restrict the withdrawals.
     */
    function setLockupPeriod(uint256 _newLockupPeriod) external {
        _whenProtocolNotPaused();
        _isValidDelegate();
        lockupPeriod = _newLockupPeriod;
    }

    /**
        @dev Update user status on StakeLocker allowlist. Only Pool Delegate can call this function.
        @param user   The address to set status for.
        @param status The status of user on allowlist.
    */
    function setAllowlistStakeLocker(address user, bool status) external {
        _whenProtocolNotPaused();
        _isValidDelegate();
        IStakeLocker(stakeLocker).setAllowlist(user, status);
    }

    /**
        @dev View claimable balance from LiqudityLocker (reflecting deposit + gain/loss).
        @param lp Liquidity Provider to check claimableFunds for 
        @return [0] = Total     amount claimable
                [1] = Principal amount claimable
                [2] = Interest  amount claimable
    */
    function claimableFunds(address lp) public view returns(uint256, uint256, uint256) {

        // Deposit is still within lockupPeriod, user has 0 claimableFunds under this condition.
        if (depositDate[lp].add(lockupPeriod) > block.timestamp) {
            return (withdrawableFundsOf(lp), 0, withdrawableFundsOf(lp)); 
        }
        else {
            uint256 userBalance    = _fromWad(balanceOf(lp));
            uint256 interestEarned = withdrawableFundsOf(lp);                                    // Calculate interest earned
            uint256 firstPenalty   = principalPenalty.mul(userBalance).div(10000);               // Calculate flat principal penalty
            uint256 totalPenalty   = calcWithdrawPenalty(interestEarned.add(firstPenalty), lp);  // Calculate total penalty

            return (
                userBalance.sub(totalPenalty).add(interestEarned), 
                userBalance.sub(totalPenalty), 
                interestEarned
            );
        }
    }

    /** 
        @dev Calculates the value of BPT in units of liquidityAsset.
        @param _bPool          Address of Balancer pool
        @param _liquidityAsset Asset used by Pool for liquidity to fund loans
        @param _staker         Address that deposited BPTs to stakeLocker
        @param _stakeLocker    Escrows BPTs deposited by staker
        @return USDC value of staker BPTs
    */
    function BPTVal(
        address _bPool,
        address _liquidityAsset,
        address _staker,
        address _stakeLocker
    ) public view returns (uint256) {
        return PoolLib.BPTVal(_bPool, _liquidityAsset, _staker, _stakeLocker);
    }

    /**
        @dev Liquidate the loan. Pool delegate could liquidate a loan only when loan completes its grace period.
        Pool delegate can claim its proportion of recovered funds from liquidation using the `claim()` function.
        @param loan      Address of the loan contract to liquidate
        @param dlFactory Address of the debt locker factory that is used to pull corresponding debt locker
     */
    function triggerDefault(address loan, address dlFactory) external {
        _whenProtocolNotPaused();
        _isValidDelegate();
        IDebtLocker(debtLockers[loan][dlFactory]).triggerDefault();
    }

    /**
        @dev Withdraws all claimable interest from the `liquidityLocker` for a user using `interestSum` accounting.
    */
    function withdrawFunds() public override {
        _whenProtocolNotPaused();
        uint256 withdrawableFunds = _prepareWithdraw();

        ILiquidityLocker(liquidityLocker).transfer(msg.sender, withdrawableFunds);

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

    /**
      @dev Checks whether pool state is `Finalized`?
      @return bool Boolean value to know the status of state.
     */
    function isPoolFinalized() external view returns(bool) {
        return poolState == State.Finalized;
    }

    /**
        @dev Utility to convert to WAD precision.
        @param amt Amount to convert
    */
    function _toWad(uint256 amt) internal view returns(uint256) {
        return amt.mul(WAD).div(10 ** liquidityAssetDecimals);
    }

    /**
        @dev Utility to convert from WAD precision to liquidtyAsset precision.
        @param amt Amount to convert
    */
    function _fromWad(uint256 amt) internal view returns(uint256) {
        return amt.mul(10 ** liquidityAssetDecimals).div(WAD);
    }

    /**
        @dev Fetch the balance of this Pool's LiquidityLocker.
        @return Balance of LiquidityLocker
    */
    function _balanceOfLiquidityLocker() internal view returns(uint256) {
        return liquidityAsset.balanceOf(liquidityLocker);
    } 

    /**
        @dev Utility to check current state of Pool againt provided state.
        @param _state Enum of desired Pool state
    */
    function _isValidState(State _state) internal view {
        require(poolState == _state, "Pool:STATE_CHECK");
    }

    /**
        @dev Utility to return if msg.sender is the Pool Delegate.
    */
    function _isValidDelegate() internal view {
        require(msg.sender == poolDelegate, "Pool:INVALID_DELEGATE");
    }

    /**
        @dev Utility to return MapleGlobals interface.
    */
    function _globals(address poolFactory) internal view returns (IGlobals) {
        return IGlobals(ILoanFactory(poolFactory).globals());
    }

    /**
        @dev Utility to emit BalanceUpdated event for LiquidityLocker.
    */
    function _emitBalanceUpdatedEvent() internal {
        emit BalanceUpdated(liquidityLocker, address(liquidityAsset), _balanceOfLiquidityLocker());
    }

    /**
        @dev Transfers liquidity asset from address(this) to given `to` address.
        @param to    Address to transfer liquidityAsset
        @param value Amount of liquidity asset that gets transferred
    */
    function _transferLiquidityAsset(address to, uint256 value) internal {
        liquidityAsset.safeTransfer(to, value);
    }

    /**
        @dev Function to determine if msg.sender is eligible to setLiquidityCap for security reasons.
    */
    function _isValidDelegateOrAdmin() internal {
        require(msg.sender == poolDelegate || admins[msg.sender], "Pool:UNAUTHORIZED");
    }

    /**
        @dev Function to block functionality of functions when protocol is in a paused state.
    */
    function _whenProtocolNotPaused() internal {
        require(!_globals(superFactory).protocolPaused(), "Pool:PROTOCOL_PAUSED");
    }
}
