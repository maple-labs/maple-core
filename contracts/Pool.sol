// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "./token/PoolFDT.sol";

import "./interfaces/IBPool.sol";
import "./interfaces/IDebtLocker.sol";
import "./interfaces/IMapleGlobals.sol";
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

    IERC20  public immutable liquidityAsset;  // The asset deposited by lenders into the LiquidityLocker, for funding Loans

    address public immutable poolDelegate;     // Pool Delegate address, maintains full authority over the Pool
    address public immutable liquidityLocker;  // The LiquidityLocker owned by this contract
    address public immutable stakeAsset;       // The asset deposited by stakers into the StakeLocker (BPTs), for liquidation during default events
    address public immutable stakeLocker;      // Address of the StakeLocker, escrowing stakeAsset
    address public immutable superFactory;     // The factory that deployed this Loan

    uint256 private immutable liquidityAssetDecimals;  // decimals() precision for the liquidityAsset

    uint256 public           stakingFee;   // Fee for stakers   (in basis points)
    uint256 public immutable delegateFee;  // Fee for delegates (in basis points)

    uint256 public principalOut;  // Sum of all outstanding principal on Loans
    uint256 public liquidityCap;  // Amount of liquidity tokens accepted by the Pool
    uint256 public lockupPeriod;  // Period of time from a user's depositDate that they cannot withdraw any funds

    bool public openToPublic;  // Boolean opening Pool to public for LP deposits

    enum State { Initialized, Finalized, Deactivated }
    State public poolState;

    mapping(address => uint256)                     public depositDate;                // Used for withdraw penalty calculation
    mapping(address => mapping(address => address)) public debtLockers;                // Address of the `DebtLocker` contract corresponds to [Loan][DebtLockerFactory].
    mapping(address => bool)                        public poolAdmins;                 // Pool Admin addresses who have permission to do certain operations in case of disaster mgt.
    mapping(address => bool)                        public allowedLiquidityProviders;  // Map that contains the list of address to enjoy the early access of the pool.
    mapping(address => uint256)                     public withdrawCooldown;           // Timestamp of when LP calls `intendToWithdraw()`
    mapping(address => mapping(address => uint256)) public custodyAllowance;           // Amount of PoolFDTs that are "locked" at a certain address
    mapping(address => uint256)                     public totalCustodyAllowance;      // Total amount of PoolFDTs that are "locked" for a given user, cannot be greater than balance

    event              LoanFunded(address indexed loan, address debtLocker, uint256 amountFunded);
    event                   Claim(address indexed loan, uint256 interest, uint256 principal, uint256 fee, uint256 stakeLockerFee, uint256 poolDelegateFee);
    event          BalanceUpdated(address indexed who, address indexed token, uint256 balance);
    event         CustodyTransfer(address indexed custodian, address indexed from, address indexed to, uint256 amount);
    event CustodyAllowanceChanged(address indexed tokenHolder, address indexed custodian, uint256 oldAllowance, uint256 newAllowance);
    event         LPStatusChanged(address indexed user, bool status);
    event         LiquidityCapSet(uint256 newLiquidityCap);
    event         LockupPeriodSet(uint256 newLockupPeriod);
    event           StakingFeeSet(uint256 newStakingFee);
    event        PoolStateChanged(State state);
    event                Cooldown(address indexed lp, uint256 cooldown);
    event      PoolOpenedToPublic(bool isOpen);
    event            PoolAdminSet(address poolAdmin, bool allowed);
    
    event DefaultSuffered(
        address indexed loan,
        uint256 defaultSuffered,
        uint256 bptsBurned,
        uint256 bptsReturned,
        uint256 liquidityAssetRecoveredFromBurn
    );

    /**
        Universal accounting law: fdtTotalSupply = liquidityLockerBal + principalOut - interestSum + poolLosses
                                  liquidityLockerBal + principalOut = fdtTotalSupply + interestSum - poolLosses
    */

    /**
        @dev   Constructor for a Pool.
        @dev   It emits a `PoolStateChanged` event.
        @param _poolDelegate   Address that has manager privileges of the Pool.
        @param _liquidityAsset Asset used to fund the Pool, It gets escrowed in `LiquidityLocker`.
        @param _stakeAsset     Asset escrowed in StakeLocker.
        @param _slFactory      Factory used to instantiate StakeLocker.
        @param _llFactory      Factory used to instantiate LiquidityLocker.
        @param _stakingFee     Fee that `stakers` earn on interest, in basis points.
        @param _delegateFee    Fee that `_poolDelegate` earns on interest, in basis points.
        @param _liquidityCap   Max amount of liquidityAsset accepted by the Pool.
        @param name            Name of Pool token.
        @param symbol          Symbol of Pool token.
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

        lockupPeriod = 180 days;

        emit PoolStateChanged(State.Initialized);
    }

    /*******************************/
    /*** Pool Delegate Functions ***/
    /*******************************/

    /**
        @dev Finalize the Pool, enabling deposits. Checks Pool Delegate amount deposited to StakeLocker. Only the Pool Delegate can call this function.
        @dev It emits a `PoolStateChanged` event.
    */
    function finalize() external {
        _isValidDelegateAndProtocolNotPaused();
        _isValidState(State.Initialized);
        (,, bool stakeSufficient,,) = getInitialStakeRequirements();
        require(stakeSufficient, "P:INSUFFICIENT_STAKE");
        poolState = State.Finalized;
        emit PoolStateChanged(poolState);
    }

    /**
        @dev   Fund a loan for amt, utilize the supplied dlFactory for debt lockers. Only the Pool Delegate can call this function.
        @param loan      Address of the loan to fund.
        @param dlFactory The DebtLockerFactory to utilize.
        @param amt       Amount to fund the loan.
    */
    function fundLoan(address loan, address dlFactory, uint256 amt) external {
        _isValidDelegateAndProtocolNotPaused();
        _isValidState(State.Finalized);
        principalOut = principalOut.add(amt);
        PoolLib.fundLoan(debtLockers, superFactory, liquidityLocker, loan, dlFactory, amt);
        _emitBalanceUpdatedEvent();
    }

    /**
        @dev   Liquidate the loan. Pool delegate could liquidate a loan only when loan completes its grace period.
               Pool delegate can claim its proportion of recovered funds from liquidation using the `claim()` function.
               Only the Pool Delegate can call this function.
        @param loan      Address of the loan contract to liquidate.
        @param dlFactory Address of the debt locker factory that is used to pull corresponding debt locker.
     */
    function triggerDefault(address loan, address dlFactory) external {
        _isValidDelegateAndProtocolNotPaused();
        IDebtLocker(debtLockers[loan][dlFactory]).triggerDefault();
    }

    /**
        @dev    Claim available funds for loan through specified DebtLockerFactory. Only the Pool Delegate or a Pool Admin can call this function.
        @dev    It emits a `BalanceUpdated` event.
        @dev    It emits a `Claim` event.
        @param  loan      Address of the loan to claim from.
        @param  dlFactory The DebtLockerFactory (always maps to a single debt locker).
        @return claimInfo The claim details.
                    claimInfo [0] = Total amount claimed
                    claimInfo [1] = Interest  portion claimed
                    claimInfo [2] = Principal portion claimed
                    claimInfo [3] = Fee       portion claimed
                    claimInfo [4] = Excess    portion claimed
                    claimInfo [5] = Recovered portion claimed (from liquidations)
                    claimInfo [6] = Default suffered
    */
    function claim(address loan, address dlFactory) external returns(uint256[7] memory claimInfo) {
        _whenProtocolNotPaused();
        _isValidDelegateOrPoolAdmin();
        claimInfo = IDebtLocker(debtLockers[loan][dlFactory]).claim();

        (uint256 poolDelegatePortion, uint256 stakeLockerPortion, uint256 principalClaim, uint256 interestClaim) = PoolLib.calculateClaimAndPortions(claimInfo, delegateFee, stakingFee);

        // Subtract outstanding principal by principal claimed plus excess returned
        // Considers possible principalClaim overflow if liquidityAsset is transferred directly into Loan
        if (principalClaim <= principalOut) {
            principalOut = principalOut - principalClaim;
        } else {
            interestClaim  = interestClaim.add(principalClaim - principalOut);  // Distribute principalClaim overflow as interest to LPs
            principalClaim = principalOut;                                      // Set principalClaim to principalOut so correct amount gets transferred
            principalOut   = 0;                                                 // Set principalOut to zero to avoid subtraction overflow
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

        emit Claim(loan, interestClaim, principalClaim, claimInfo[3], stakeLockerPortion, poolDelegatePortion);
    }

    /**
        @dev   Helper function if a claim has been made and there is a non-zero defaultSuffered amount.
        @dev   It emits a `DefaultSuffered` event.
        @param loan            Address of loan that has defaulted.
        @param defaultSuffered Losses suffered from default after liquidation.
    */
    function _handleDefault(address loan, uint256 defaultSuffered) internal {

        (uint256 bptsBurned, uint256 postBurnBptBal, uint256 liquidityAssetRecoveredFromBurn) = PoolLib.handleDefault(liquidityAsset, stakeLocker, stakeAsset, defaultSuffered);

        // If BPT burn is not enough to cover full default amount, pass on losses to LPs with PoolFDT loss accounting
        if (defaultSuffered > liquidityAssetRecoveredFromBurn) {
            poolLosses = poolLosses.add(defaultSuffered - liquidityAssetRecoveredFromBurn);
            updateLossesReceived();
        }

        // Transfer liquidityAsset from burn to liquidityLocker
        liquidityAsset.safeTransfer(liquidityLocker, liquidityAssetRecoveredFromBurn);

        principalOut = principalOut.sub(defaultSuffered);  // Subtract rest of Loan's principal from principalOut

        emit DefaultSuffered(
            loan,                            // Which loan defaultSuffered is from
            defaultSuffered,                 // Total default suffered from loan by Pool after liquidation
            bptsBurned,                      // Amount of BPTs burned from stakeLocker
            postBurnBptBal,                  // Remaining BPTs in stakeLocker post-burn
            liquidityAssetRecoveredFromBurn  // Amount of liquidityAsset recovered from burning BPTs
        );
    }

    /**
        @dev Triggers deactivation, permanently shutting down the pool. Must have less than 100 USD worth of liquidityAsset principalOut.
             Only the Pool Delegate can call this function.
        @dev It emits a `PoolStateChanged` event.
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
        @dev   Set `liquidityCap`. Only the Pool Delegate or a Pool Admin can call this function.
        @dev   It emits a `LiquidityCapSet` event.
        @param newLiquidityCap New liquidityCap value.
    */
    function setLiquidityCap(uint256 newLiquidityCap) external {
        _whenProtocolNotPaused();
        _isValidDelegateOrPoolAdmin();
        liquidityCap = newLiquidityCap;
        emit LiquidityCapSet(newLiquidityCap);
    }

    /**
        @dev   Set the lockup period. Only the Pool Delegate can call this function.
        @dev   It emits a `LockupPeriodSet` event.
        @param newLockupPeriod New lockup period used to restrict the withdrawals.
     */
    function setLockupPeriod(uint256 newLockupPeriod) external {
        _isValidDelegateAndProtocolNotPaused();
        require(newLockupPeriod <= lockupPeriod, "P:INVALID_VALUE");
        lockupPeriod = newLockupPeriod;
        emit LockupPeriodSet(newLockupPeriod);
    }

    /**
        @dev   Update staking fee. Only the Pool Delegate can call this function.
        @dev   It emits a `StakingFeeSet` event.
        @param newStakingFee New staking fee.
    */
    function setStakingFee(uint256 newStakingFee) external {
        _isValidDelegateAndProtocolNotPaused();
        require(newStakingFee.add(delegateFee) <= 10_000, "P:INVALID_FEE");
        stakingFee = newStakingFee;
        emit StakingFeeSet(newStakingFee);
    }

    /**
        @dev   Update user status on Pool allowlist. Only the Pool Delegate can call this function.
        @dev   It emits an `LPStatusChanged` event.
        @param user   The address to set status for.
        @param status The status of user on allowlist.
    */
    function setAllowList(address user, bool status) external {
        _isValidDelegateAndProtocolNotPaused();
        allowedLiquidityProviders[user] = status;
        emit LPStatusChanged(user, status);
    }

    /**
        @dev   Set pool admin. Only the Pool Delegate can call this function.
        @dev   It emits a `PoolAdminSet` event.
        @param poolAdmin An address being allowed or disallowed as a Pool Admin.
        @param allowed Status of an pool admin.
    */
    function setPoolAdmin(address poolAdmin, bool allowed) external {
        _isValidDelegateAndProtocolNotPaused();
        poolAdmins[poolAdmin] = allowed;
        emit PoolAdminSet(poolAdmin, allowed);
    }

    /**
        @dev   Set public pool access. Only the Pool Delegate can call this function.
        @dev   It emits a `PoolOpenedToPublic` event.
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
        @dev   Liquidity providers can deposit liquidityAsset into the LiquidityLocker, minting FDTs.
        @dev   It emits a `Cooldown` event.
        @param amt Amount of liquidityAsset to deposit
    */
    function deposit(uint256 amt) external {
        _whenProtocolNotPaused();
        _isValidState(State.Finalized);
        require(isDepositAllowed(amt), "P:DEPOSIT_NOT_ALLOWED");

        withdrawCooldown[msg.sender] = uint256(0);  // Reset withdrawCooldown if LP had previously intended to withdraw

        uint256 wad = _toWad(amt);
        PoolLib.updateDepositDate(depositDate, balanceOf(msg.sender), wad, msg.sender);

        liquidityAsset.safeTransferFrom(msg.sender, liquidityLocker, amt);
        _mint(msg.sender, wad);

        _emitBalanceUpdatedEvent();
        emit Cooldown(msg.sender, uint256(0));
    }

    /**
        @dev Activates the cooldown period to withdraw. It can't be called if the user is not providing liquidity.
    **/
    function intendToWithdraw() external {
        PoolLib.intendToWithdraw(withdrawCooldown, balanceOf(msg.sender));
    }

    /**
        @dev Cancels an initiated withdrawal by resetting withdrawCooldown.
    **/
    function cancelWithdraw() external {
        PoolLib.cancelWithdraw(withdrawCooldown);
    }

    /**
        @dev   Liquidity providers can withdraw liquidityAsset from the LiquidityLocker, burning PoolFDTs.
        @param amt Amount of liquidityAsset to withdraw.
    */
    function withdraw(uint256 amt) external {
        _whenProtocolNotPaused();
        uint256 wad = _toWad(amt);

        require(PoolLib.isWithdrawAllowed(withdrawCooldown[msg.sender], _globals(superFactory)), "P:WITHDRAW_NOT_ALLOWED");
        require(depositDate[msg.sender].add(lockupPeriod) <= block.timestamp,                    "P:FUNDS_LOCKED");

        _burn(msg.sender, wad);  // Burn the corresponding FDT balance
        withdrawFunds();         // Transfer full entitled interest, decrement `interestSum`

        // Transfer amount that is due after realized losses are accounted for.
        // recognizedLosses are absorbed by the LP.
        _transferLiquidityLockerFunds(msg.sender, amt.sub(recognizeLosses()));

        _emitBalanceUpdatedEvent();
    }

    /**
        @dev   Transfer PoolFDTs.
        @param from Address sending   PoolFDTs.
        @param to   Address receiving PoolFDTs.
        @param wad  Amount of PoolFDTs to transfer.
    */
    function _transfer(address from, address to, uint256 wad) internal override {
        _whenProtocolNotPaused();
        PoolLib.prepareTransfer(
            withdrawCooldown,
            depositDate,
            totalCustodyAllowance[from],
            balanceOf(from),
            from,
            to,
            wad,
            _globals(superFactory),
            balanceOf(to),
            recognizableLossesOf(from),
            lockupPeriod
        );
        super._transfer(from, to, wad);
    }

    /**
        @dev Withdraws all claimable interest from the `liquidityLocker` for a user using `interestSum` accounting.
    */
    function withdrawFunds() public override {
        _whenProtocolNotPaused();
        uint256 withdrawableFunds = _prepareWithdraw();

        if (withdrawableFunds == uint256(0)) return;

        _transferLiquidityLockerFunds(msg.sender, withdrawableFunds);
        _emitBalanceUpdatedEvent();

        interestSum = interestSum.sub(withdrawableFunds);

        _updateFundsTokenBalance();
    }

    /**
        @dev   Increase the custody allowance for a given `custodian` corresponds to `msg.sender`.
        @param custodian Address which will act as custodian of given `amount` for a tokenHolder.
        @param amount    Number of FDTs custodied by the custodian.
     */
    function increaseCustodyAllowance(address custodian, uint256 amount) external {
        uint256 oldAllowance      = custodyAllowance[msg.sender][custodian];
        uint256 newAllowance      = oldAllowance.add(amount);
        uint256 newTotalAllowance = totalCustodyAllowance[msg.sender].add(amount);

        PoolLib.increaseCustodyAllowanceChecks(custodian, amount, newTotalAllowance, balanceOf(msg.sender));
        
        custodyAllowance[msg.sender][custodian] = newAllowance;
        totalCustodyAllowance[msg.sender]       = newTotalAllowance;
        emit CustodyAllowanceChanged(msg.sender, custodian, oldAllowance, newAllowance);
    }

    /**
        @dev   `from` and `to` should always be equal in this implementation.
        @dev   This means that the custodian can only decrease their own allowance and unlock funds for the original owner.
        @param from   Address which holds to Pool FDTs.
        @param to     Address which going to be the new owner of the `amount` FDTs.
        @param amount Number of FDTs transferred.
     */
    function transferByCustodian(address from, address to, uint256 amount) external {
        uint256 oldAllowance = custodyAllowance[from][msg.sender];
        uint256 newAllowance = oldAllowance.sub(amount);

        PoolLib.transferByCustodianChecks(from, to, amount, oldAllowance);

        custodyAllowance[from][msg.sender] = newAllowance;
        totalCustodyAllowance[from]        = totalCustodyAllowance[from].sub(amount);
        emit CustodyTransfer(msg.sender, from, to, amount);
        emit CustodyAllowanceChanged(msg.sender, to, oldAllowance, newAllowance);
    }

    /**************************/
    /*** Governor Functions ***/
    /**************************/

    /**
        @dev   Transfer any locked funds to the Governor. Only the Governor can call this function.
        @param token Address of the token to reclaim.
    */
    function reclaimERC20(address token) external {
        PoolLib.reclaimERC20(token, address(liquidityAsset), _globals(superFactory));
    }

    /*************************/
    /*** Getter Functions ***/
    /*************************/

    /**
        @dev    Calculates the value of BPT in units of liquidityAsset.
        @param  _bPool          Address of Balancer pool
        @param  _liquidityAsset Asset used by Pool for liquidity to fund loans
        @param  _staker         Address that deposited BPTs to stakeLocker
        @param  _stakeLocker    Escrows BPTs deposited by staker
        @return USDC value of staker BPTs
    */
    function BPTVal(
        address _bPool,
        address _liquidityAsset,
        address _staker,
        address _stakeLocker
    ) external view returns (uint256) {
        return PoolLib.BPTVal(_bPool, _liquidityAsset, _staker, _stakeLocker);
    }

    /**
        @dev   Checks that the given `depositAmt` is acceptable based on current liquidityCap.
        @param depositAmt Amount of tokens (i.e liquidityAsset type) user is trying to deposit.
    */
    function isDepositAllowed(uint256 depositAmt) public view returns(bool) {
        return (openToPublic || allowedLiquidityProviders[msg.sender]) &&
               _balanceOfLiquidityLocker().add(principalOut).add(depositAmt) <= liquidityCap;
    }

    /**
        @dev    Returns information on the stake requirements.
        @return [0] = Min amount of liquidityAsset coverage from staking required.
                [1] = Present amount of liquidityAsset coverage from Pool Delegate stake.
                [2] = If enough stake is present from Pool Delegate for finalization.
                [3] = Staked BPTs required for minimum liquidityAsset coverage.
                [4] = Current staked BPTs.
    */
    function getInitialStakeRequirements() public view returns (uint256, uint256, bool, uint256, uint256) {
        return PoolLib.getInitialStakeRequirements(_globals(superFactory), stakeAsset, address(liquidityAsset), poolDelegate, stakeLocker);
    }

    /**
        @dev    Calculates BPTs required if burning BPTs for liquidityAsset, given supplied tokenAmountOutRequired.
        @param  _bPool                        Balancer pool that issues the BPTs.
        @param  _liquidityAsset               Swap out asset (e.g. USDC) to receive when burning BPTs.
        @param  _staker                       Address that deposited BPTs to stakeLocker.
        @param  _stakeLocker                  Escrows BPTs deposited by staker.
        @param  _liquidityAssetAmountRequired Amount of liquidityAsset required to recover.
        @return [0] = poolAmountIn required.
                [1] = poolAmountIn currently staked.
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
      @dev    Checks that the Pool state is `Finalized`.
      @return bool Boolean value indicating if Pool is in a Finalized state.
     */
    function isPoolFinalized() external view returns(bool) {
        return poolState == State.Finalized;
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    /**
        @dev   Utility to convert to WAD precision.
        @param amt Amount to convert.
    */
    function _toWad(uint256 amt) internal view returns(uint256) {
        return amt.mul(WAD).div(10 ** liquidityAssetDecimals);
    }

    /**
        @dev   Fetch the balance of this Pool's LiquidityLocker.
        @return Balance of LiquidityLocker.
    */
    function _balanceOfLiquidityLocker() internal view returns(uint256) {
        return liquidityAsset.balanceOf(liquidityLocker);
    }

    /**
        @dev   Checks that the current state of Pool matches the provided state.
        @param _state Enum of desired Pool state.
    */
    function _isValidState(State _state) internal view {
        require(poolState == _state, "P:INVALID_STATE");
    }

    /**
        @dev Checks that `msg.sender` is the Pool Delegate.
    */
    function _isValidDelegate() internal view {
        require(msg.sender == poolDelegate, "P:NOT_DELEGATE");
    }

    /**
        @dev Utility to return MapleGlobals interface.
    */
    function _globals(address poolFactory) internal view returns (IMapleGlobals) {
        return IMapleGlobals(IPoolFactory(poolFactory).globals());
    }

    /**
        @dev Utility to emit BalanceUpdated event for LiquidityLocker.
    */
    function _emitBalanceUpdatedEvent() internal {
        emit BalanceUpdated(liquidityLocker, address(liquidityAsset), _balanceOfLiquidityLocker());
    }

    /**
        @dev   Transfers liquidity asset from address(this) to given `to` address.
        @param to    Address to transfer liquidityAsset.
        @param value Amount of liquidity asset that gets transferred.
    */
    function _transferLiquidityAsset(address to, uint256 value) internal {
        liquidityAsset.safeTransfer(to, value);
    }

    /**
        @dev Checks that `msg.sender` is the Pool Delegate or a Pool Admin.
    */
    function _isValidDelegateOrPoolAdmin() internal view {
        require(msg.sender == poolDelegate || poolAdmins[msg.sender], "P:NOT_DELEGATE_OR_ADMIN");
    }

    /**
        @dev Checks that the protocol is not in a paused state.
    */
    function _whenProtocolNotPaused() internal view {
        require(!_globals(superFactory).protocolPaused(), "P:PROTO_PAUSED");
    }

    /**
        @dev Checks that `msg.sender` is the Pool Delegate and that the protocol is not in a paused state.
    */
    function _isValidDelegateAndProtocolNotPaused() internal view {
        _isValidDelegate();
        _whenProtocolNotPaused();
    }

    function _transferLiquidityLockerFunds(address to, uint256 value) internal {
        ILiquidityLocker(liquidityLocker).transfer(to, value);
    }
}
