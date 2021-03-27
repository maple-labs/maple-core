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
    address public immutable superFactory;     // The factory that deployed this Loan

    uint256 private immutable liquidityAssetDecimals;  // decimals() precision for the liquidityAsset

    // Universal accounting law: fdtTotalSupply = liquidityLockerBal + principalOut - interestSum + bptShortfall
    //        liquidityLockerBal + principalOut = fdtTotalSupply + interestSum - bptShortfall
    
    uint256 public immutable stakingFee;   // Fee for stakers   (in basis points)
    uint256 public immutable delegateFee;  // Fee for delegates (in basis points)

    uint256 public principalOut;      // Sum of all outstanding principal on Loans
    uint256 public principalPenalty;  // Max penalty on principal in basis points on early withdrawal
    uint256 public penaltyDelay;      // Time until total interest and principal is available after a deposit, in seconds
    uint256 public liquidityCap;      // Amount of liquidity tokens accepted by the Pool
    uint256 public lockupPeriod;      // Unix timestamp during which withdrawal is not allowed

    bool public openToPublic;  // Boolean opening Pool to public for LP deposits

    enum State { Initialized, Finalized, Deactivated }
    State public poolState;  // The current state of this pool

    mapping(address => uint256)                     public depositDate;                // Used for withdraw penalty calculation
    mapping(address => mapping(address => address)) public debtLockers;                // Address of the `DebtLocker` contract corresponds to [Loan][DebtLockerFactory].
    mapping(address => bool)                        public admins;                     // Admin addresses who have permission to do certain operations in case of disaster mgt.
    mapping(address => bool)                        public allowedLiquidityProviders;  // Map that contains the list of address to enjoy the early access of the pool.
    mapping(address => uint256)                     public depositCooldown;            // Timestamp of when LP calls `intendToWithdraw()`

    event       LoanFunded(address indexed loan, address debtLocker, uint256 amountFunded);
    event            Claim(address indexed loan, uint256 interest, uint256 principal, uint256 fee);
    event   BalanceUpdated(address indexed who,  address token, uint256 balance);
    event  LPStatusChanged(address indexed user, bool status);
    event  LiquidityCapSet(uint256 newLiquidityCap);
    event PoolStateChanged(State state);
    event         Cooldown(address staker);
    event  DefaultSuffered(
        address indexed loan, 
        uint256 defaultSuffered, 
        uint256 bptsBurned, 
        uint256 bptsReturned,
        uint256 liquidityAssetRecoveredFromBurn
    );
    event  PoolOpenedToPublic(bool isOpen);

    /**
        @dev Constructor for a Pool.
        @param  _poolDelegate   Address that has manager privileges of the Pool
        @param  _liquidityAsset Asset used to fund the Pool, It gets escrowed in `LiquidityLocker`
        @param  _stakeAsset     Asset escrowed in StakeLocker
        @param  _slFactory      Factory used to instantiate StakeLocker
        @param  _llFactory      Factory used to instantiate LiquidityLocker
        @param  _stakingFee     Fee that `stakers` earn on interest, in basis points
        @param  _delegateFee    Fee that `_poolDelegate` earns on interest, in basis points
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

        // Conduct sanity checks on Pool params
        PoolLib.poolSanityChecks(_globals(msg.sender), _liquidityAsset, _stakeAsset, _stakingFee, _delegateFee);

        // Assign variables relating to liquidityAsset
        liquidityAsset         = IERC20(_liquidityAsset);
        liquidityAssetDecimals = ERC20(_liquidityAsset).decimals();

        // Assign state variables
        stakeAsset   = _stakeAsset;
        poolDelegate = _poolDelegate;
        stakingFee   = _stakingFee;
        delegateFee  = _delegateFee;
        superFactory = msg.sender;
        liquidityCap = _liquidityCap;

        // Initialize the LiquidityLocker and StakeLocker
        stakeLocker     = address(IStakeLockerFactory(_slFactory).newLocker(_stakeAsset, _liquidityAsset));
        liquidityLocker = address(ILiquidityLockerFactory(_llFactory).newLocker(_liquidityAsset));

        // Withdrawal penalty default settings
        principalPenalty = 500;
        penaltyDelay     = 30 days;
        lockupPeriod     = 180 days;

        emit PoolStateChanged(State.Initialized);
    }

    /*******************************/
    /*** Pool Delegate Functions ***/
    /*******************************/

    /**
        @dev Finalize the Pool, enabling deposits. Checks Pool Delegate amount deposited to StakeLocker.
    */
    function finalize() external {
        _isValidDelegateAndProtocolNotPaused();
        _isValidState(State.Initialized);
        (,, bool stakeSufficient,,) = getInitialStakeRequirements();
        require(stakeSufficient, "Pool:INSUFFICIENT_STAKE");
        poolState = State.Finalized;
        emit PoolStateChanged(poolState);
    }

    /**
        @dev Fund a loan for amt, utilize the supplied dlFactory for debt lockers.
        @param  loan      Address of the loan to fund
        @param  dlFactory The DebtLockerFactory to utilize
        @param  amt       Amount to fund the loan
    */
    function fundLoan(address loan, address dlFactory, uint256 amt) external {
        _isValidDelegateAndProtocolNotPaused();
        _isValidState(State.Finalized);
        principalOut = principalOut.add(amt);
        PoolLib.fundLoan(debtLockers, superFactory, liquidityLocker, loan, dlFactory, amt);
        _emitBalanceUpdatedEvent();
    }

    /**
        @dev Liquidate the loan. Pool delegate could liquidate a loan only when loan completes its grace period.
        Pool delegate can claim its proportion of recovered funds from liquidation using the `claim()` function.
        @param loan      Address of the loan contract to liquidate
        @param dlFactory Address of the debt locker factory that is used to pull corresponding debt locker
     */
    function triggerDefault(address loan, address dlFactory) external {
        _isValidDelegateAndProtocolNotPaused();
        IDebtLocker(debtLockers[loan][dlFactory]).triggerDefault();
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
        _isValidDelegateOrAdmin();
        uint256[7] memory claimInfo = IDebtLocker(debtLockers[loan][dlFactory]).claim();

        (uint256 poolDelegatePortion, uint256 stakeLockerPortion, uint256 principalClaim, uint256 interestClaim) = PoolLib.calculateClaimAndPortions(claimInfo, delegateFee, stakingFee);

        // Subtract outstanding principal by principal claimed plus excess returned
        // Considers possible overflow if loanAsset is transferred directly into Loan
        if (principalClaim <= principalOut) {
            principalOut = principalOut - principalClaim;
        } else {
            interestClaim  = interestClaim.add(principalClaim - principalOut);  // Distribute principalClaim overflow as interest to LPs
            principalClaim = principalOut;                                      // Set principalClaim to principalOut so correct amount gets transferred
            principalOut   = 0;                                                 // Set principalOUt to zero to avoid subtraction overflow
        }

        // Accounts for rounding error in stakeLocker/poolDelegate/liquidityLocker interest split
        interestSum = interestSum.add(interestClaim);

        _transferLiquidityAsset(poolDelegate, poolDelegatePortion);  // Transfer fee and portion of interest to pool delegate
        _transferLiquidityAsset(stakeLocker,  stakeLockerPortion);   // Transfer portion of interest to stakeLocker

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

        emit Claim(loan, interestClaim, principalClaim, claimInfo[3]);  // TODO: Discuss with offchain team about requirements for event

        return claimInfo;  // TODO: Discuss with offchain team about requirements for return
    }

    /**
        @dev Helper function if a claim has been made and there is a non-zero defaultSuffered amount.
        @param loan            Address of loan that has defaulted
        @param defaultSuffered Losses suffered from default after liquidation
    */
    function _handleDefault(address loan, uint256 defaultSuffered) internal {

        (uint256 bptsBurned, uint256 bptsReturned, uint256 liquidityAssetRecoveredFromBurn) = PoolLib.handleDefault(liquidityAsset, stakeLocker, stakeAsset, loan, defaultSuffered);

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
        @dev Pool Delegate triggers deactivation, permanently shutting down the pool. Must have less than 100 USD worth of liquidityAsset principalOut.
    */
    function deactivate() external {
        _isValidDelegateAndProtocolNotPaused();
        _isValidState(State.Finalized);
        PoolLib.validateDeactivation(_globals(superFactory), principalOut, address(liquidityAsset));
        poolState = State.Deactivated;
        emit PoolStateChanged(poolState);
    }

    /**************************************/
    /*** Pool Delegate Setter Functions ***/
    /**************************************/

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
        @dev Set the amount of time required to recover 100% of claimable funds 
             (i.e. calcWithdrawPenalty = 0)
        @param _penaltyDelay Effective time needed in pool for user to be able to claim 100% of funds
    */
    function setPenaltyDelay(uint256 _penaltyDelay) external {
        _isValidDelegateAndProtocolNotPaused();
        penaltyDelay = _penaltyDelay;
    }

    /**
        @dev Set the principal penalty. Only Pool Delegate can call this function.
        @param _newPrincipalPenalty New principal penalty percentage (in basis points) that corresponds to withdrawal amount
    */
    function setPrincipalPenalty(uint256 _newPrincipalPenalty) external {
        _isValidDelegateAndProtocolNotPaused();
        principalPenalty = _newPrincipalPenalty;
    }

    /**
        @dev Set the lockup period. Only Pool Delegate can call this function.
        @param _newLockupPeriod New lockup period used to restrict the withdrawals.
     */
    function setLockupPeriod(uint256 _newLockupPeriod) external {
        _isValidDelegateAndProtocolNotPaused();
        require(_newLockupPeriod <= lockupPeriod, "Pool:INVALID_VALUE");
        lockupPeriod = _newLockupPeriod;
    }

    /**
        @dev Update user status on Pool allowlist. Only Pool Delegate can call this function.
        @param user   The address to set status for.
        @param status The status of user on allowlist.
    */
    function setAllowList(address user, bool status) external {
        _isValidDelegateAndProtocolNotPaused();
        allowedLiquidityProviders[user] = status;
        emit LPStatusChanged(user, status);
    }

    /**
        @dev Update user status on StakeLocker allowlist. Only Pool Delegate can call this function.
        @param user   The address to set status for.
        @param status The status of user on allowlist.
    */
    function setAllowlistStakeLocker(address user, bool status) external {
        _isValidDelegateAndProtocolNotPaused();
        IStakeLocker(stakeLocker).setAllowlist(user, status);
    }

    /**
        @dev Set admin
        @param newAdmin new admin address.
        @param allowed Status of an admin.
    */
    function setAdmin(address newAdmin, bool allowed) external {
        _isValidDelegateAndProtocolNotPaused();
        admins[newAdmin] = allowed;
    }

    /**
        @dev Set public pool access. Only Pool Delegate can call this function.
        @param open Public pool access status.
    */
    function setOpenToPublic(bool open) external {
        _isValidDelegateAndProtocolNotPaused();
        openToPublic = open;
        emit PoolOpenedToPublic(open);
    }

    /************************************/
    /*** Liquidity Provider Functions ***/
    /************************************/

    /**
        @dev Liquidity providers can deposit liquidityAsset into the LiquidityLocker, minting FDTs.
        @param amt Amount of liquidityAsset to deposit
    */
    function deposit(uint256 amt) external {
        _whenProtocolNotPaused();
        _isValidState(State.Finalized);
        require(isDepositAllowed(amt), "Pool:NOT_ALLOWED");
        liquidityAsset.safeTransferFrom(msg.sender, liquidityLocker, amt);
        uint256 wad = _toWad(amt);

        PoolLib.updateDepositDate(depositDate, balanceOf(msg.sender), wad, msg.sender);
        _mint(msg.sender, wad);
        _emitBalanceUpdatedEvent();
    }

    /**
        @dev Activates the cooldown period to withdraw. It can't be called if the user is not providing liquidity.
    **/
    function intendToWithdraw() external {
        PoolLib.intendToWithdraw(depositCooldown, balanceOf(msg.sender));
    }

    /**
        @dev Liquidity providers can withdraw liquidityAsset from the LiquidityLocker, burning FDTs.
        @param amt Amount of liquidityAsset to withdraw
    */
    function withdraw(uint256 amt) external {
        _whenProtocolNotPaused();
        PoolLib.isCooldownFinished(depositCooldown[msg.sender], _globals(superFactory));
        uint256 wad    = _toWad(amt);
        uint256 fdtAmt = wad == totalSupply() && wad > 0 ? wad - 1 : wad;  // If last withdraw, subtract 1 wei to maintain FDT accounting
        require(balanceOf(msg.sender) >= fdtAmt, "Pool:USER_BAL_LT_AMT");
        require(depositDate[msg.sender].add(lockupPeriod) <= block.timestamp, "Pool:FUNDS_LOCKED");

        uint256 allocatedInterest = withdrawableFundsOf(msg.sender);                                     // FDT accounting interest
        uint256 priPenalty        = principalPenalty.mul(amt).div(10000);                                // Calculate flat principal penalty
        uint256 totPenalty        = calcWithdrawPenalty(allocatedInterest.add(priPenalty), msg.sender);  // Calculate total penalty

        depositCooldown[msg.sender] = uint256(0);  // Reset cooldown time no matter what transfer amount is

        _burn(msg.sender, fdtAmt);  // Burn the corresponding FDT balance
        withdrawFunds();            // Transfer full entitled interest, decrement `interestSum`

        interestSum = interestSum.add(totPenalty);  // Update the `interestSum` with the penalty amount
        updateFundsReceived();                      // Update the `pointsPerShare` using this as fundsTokenBalance is incremented by `totPenalty`

        // Amount that is due after penalties and realized losses are accounted for. 
        // Total penalty is distributed to other LPs as interest, recognizedLosses are absorbed by the LP.
        uint256 due = amt.sub(totPenalty).sub(recognizeLosses());

        // Transfer amt - totPenalty - recognizedLosses
        _transferLiquidityLockerFunds(msg.sender, due);

        _emitBalanceUpdatedEvent();
    }

    /**
        @dev Transfer PoolFDTs.
        @param from Address sending   PoolFDTs
        @param to   Address receiving PoolFDTs
        @param wad  Amount of PoolFDTs to transfer
    */
    function _transfer(address from, address to, uint256 wad) internal override {
        _whenProtocolNotPaused();
        require(recognizableLossesOf(from) == uint256(0), "Pool:NOT_ALLOWED");
        PoolLib.prepareTransfer(depositCooldown, depositDate, from, to, wad, _globals(superFactory), balanceOf(to));
        super._transfer(from, to, wad);
    }

    /**
        @dev Withdraws all claimable interest from the `liquidityLocker` for a user using `interestSum` accounting.
    */
    function withdrawFunds() public override {
        _whenProtocolNotPaused();
        uint256 withdrawableFunds = _prepareWithdraw();

        if (withdrawableFunds > uint256(0)) { 
            _transferLiquidityLockerFunds(msg.sender, withdrawableFunds);

            interestSum = interestSum.sub(withdrawableFunds);

            _updateFundsTokenBalance();
        }
    }

    /**************************/
    /*** Governor Functions ***/
    /**************************/

    /**
        @dev Transfer any locked funds to the governor.
        @param token Address of the token that need to reclaimed.
     */
    function reclaimERC20(address token) external {
        PoolLib.reclaimERC20(token, address(liquidityAsset), _globals(superFactory));
    }

    /*************************/
    /*** Getter Functions ***/
    /*************************/

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
        @dev View claimable balance from LiqudityLocker (reflecting deposit + gain/loss).
        @param lp Liquidity Provider to check claimableFunds for 
        @return total     Total     amount claimable
        @return principal Principal amount claimable
        @return interest  Interest  amount claimable
    */
    function claimableFunds(address lp) public view returns(uint256 total, uint256 principal, uint256 interest) {
        (total, principal, interest) = 
            PoolLib.claimableFunds(
                withdrawableFundsOf(lp), 
                depositDate[lp], 
                lockupPeriod, 
                penaltyDelay, 
                balanceOf(lp), 
                principalPenalty, 
                liquidityAssetDecimals
            );
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
        @dev Check whether the given `depositAmt` is acceptable based on current liquidityCap.
        @param depositAmt Amount of tokens (i.e loanAsset type) user is trying to deposit
    */
    function isDepositAllowed(uint256 depositAmt) public view returns(bool) {
        bool isValidLP = openToPublic || allowedLiquidityProviders[msg.sender];
        return _balanceOfLiquidityLocker().add(principalOut).add(depositAmt) <= liquidityCap && isValidLP;
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
        @param  _liquidityAsset               Swap out asset (e.g. USDC) to receive when burning BPTs
        @param  _staker                       Address that deposited BPTs to stakeLocker
        @param  _stakeLocker                  Escrows BPTs deposited by staker
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
    ) external view returns (uint256, uint256) {
        return PoolLib.getPoolSharesRequired(_bPool, _liquidityAsset, _staker, _stakeLocker, _liquidityAssetAmountRequired);
    }

    /**
      @dev Checks whether pool state is `Finalized`?
      @return bool Boolean value to know the status of state.
     */
    function isPoolFinalized() external view returns(bool) {
        return poolState == State.Finalized;
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    /**
        @dev Utility to convert to WAD precision.
        @param amt Amount to convert
    */
    function _toWad(uint256 amt) internal view returns(uint256) {
        return amt.mul(WAD).div(10 ** liquidityAssetDecimals);
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
        require(poolState == _state, "Pool:INVALID_STATE");
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
        return IGlobals(IPoolFactory(poolFactory).globals());
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

    function _isValidDelegateAndProtocolNotPaused() internal {
        _isValidDelegate();
        _whenProtocolNotPaused();
    }

    function _transferLiquidityLockerFunds(address to, uint256 value) internal {
        ILiquidityLocker(liquidityLocker).transfer(to, value);
    }
}
