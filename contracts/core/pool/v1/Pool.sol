// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/SafeERC20.sol";

import "libraries/pool/v1/PoolLib.sol";

import "../../debt-locker/v1/interfaces/IDebtLocker.sol";
import "../..//globals/v1/interfaces/IMapleGlobals.sol";
import "../../liquidity-locker/v1/interfaces/ILiquidityLocker.sol";
import "../../liquidity-locker/v1/interfaces/ILiquidityLockerFactory.sol";
import "../../stake-locker/v1/interfaces/IStakeLocker.sol";
import "../../stake-locker/v1/interfaces/IStakeLockerFactory.sol";

import "./interfaces/IPool.sol";
import "./interfaces/IPoolFactory.sol";

import "./PoolFDT.sol";

/// @title Pool maintains all accounting and functionality related to Pools.
contract Pool is IPool, PoolFDT {

    using SafeMath  for uint256;
    using SafeERC20 for IERC20;

    uint256 constant WAD = 10 ** 18;

    uint8 public override constant DL_FACTORY = 1;

    IERC20 public override immutable liquidityAsset;

    address public override immutable poolDelegate;
    address public override immutable liquidityLocker;
    address public override immutable stakeAsset;
    address public override immutable stakeLocker;
    address public override immutable superFactory;

    uint256 private immutable liquidityAssetDecimals;  // The precision for the Liquidity Asset (i.e. `decimals()`).

    uint256 public override           stakingFee;
    uint256 public override immutable delegateFee;

    uint256 public override principalOut;
    uint256 public override liquidityCap;
    uint256 public override lockupPeriod;

    bool public override openToPublic;

    State public override poolState;

    mapping(address => uint256)                     public override depositDate;
    mapping(address => mapping(address => address)) public override debtLockers;
    mapping(address => bool)                        public override poolAdmins;
    mapping(address => bool)                        public override allowedLiquidityProviders;
    mapping(address => uint256)                     public override withdrawCooldown;
    mapping(address => mapping(address => uint256)) public override custodyAllowance;
    mapping(address => uint256)                     public override totalCustodyAllowance;

    /**
        Universal accounting law:
                                       fdtTotalSupply = liquidityLockerBal + principalOut - interestSum + poolLosses
            fdtTotalSupply + interestSum - poolLosses = liquidityLockerBal + principalOut
    */

    /**
        @dev   Constructor for a Pool. 
        @dev   It emits a `PoolStateChanged` event. 
        @param _poolDelegate   Address that has manager privileges of the Pool.
        @param _liquidityAsset Asset used to fund the Pool, It gets escrowed in LiquidityLocker.
        @param _stakeAsset     Asset escrowed in StakeLocker.
        @param _slFactory      Factory used to instantiate the StakeLocker.
        @param _llFactory      Factory used to instantiate the LiquidityLocker.
        @param _stakingFee     Fee that Stakers earn on interest, in basis points.
        @param _delegateFee    Fee that the Pool Delegate earns on interest, in basis points.
        @param _liquidityCap   Max amount of Liquidity Asset accepted by the Pool.
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

        // Conduct sanity checks on Pool parameters.
        PoolLib.poolSanityChecks(_globals(msg.sender), _liquidityAsset, _stakeAsset, _stakingFee, _delegateFee);

        // Assign variables relating to the Liquidity Asset.
        liquidityAsset         = IERC20(_liquidityAsset);
        liquidityAssetDecimals = ERC20(_liquidityAsset).decimals();

        // Assign state variables.
        stakeAsset   = _stakeAsset;
        poolDelegate = _poolDelegate;
        stakingFee   = _stakingFee;
        delegateFee  = _delegateFee;
        superFactory = msg.sender;
        liquidityCap = _liquidityCap;

        // Instantiate the LiquidityLocker and the StakeLocker.
        stakeLocker     = address(IStakeLockerFactory(_slFactory).newLocker(_stakeAsset, _liquidityAsset));
        liquidityLocker = address(ILiquidityLockerFactory(_llFactory).newLocker(_liquidityAsset));

        lockupPeriod = 180 days;

        emit PoolStateChanged(State.Initialized);
    }

    /*******************************/
    /*** Pool Delegate Functions ***/
    /*******************************/

    function finalize() external override {
        _isValidDelegateAndProtocolNotPaused();
        _isValidState(State.Initialized);
        (,, bool stakeSufficient,,) = getInitialStakeRequirements();
        require(stakeSufficient, "P:INSUF_STAKE");
        poolState = State.Finalized;
        emit PoolStateChanged(poolState);
    }

    function fundLoan(address loan, address dlFactory, uint256 amt) external override {
        _isValidDelegateAndProtocolNotPaused();
        _isValidState(State.Finalized);
        principalOut = principalOut.add(amt);
        PoolLib.fundLoan(debtLockers, superFactory, liquidityLocker, loan, dlFactory, amt);
        _emitBalanceUpdatedEvent();
    }

    function triggerDefault(address loan, address dlFactory) external override {
        _isValidDelegateAndProtocolNotPaused();
        IDebtLocker(debtLockers[loan][dlFactory]).triggerDefault();
    }

    function claim(address loan, address dlFactory) external override returns (uint256[7] memory claimInfo) {
        _whenProtocolNotPaused();
        _isValidDelegateOrPoolAdmin();
        claimInfo = IDebtLocker(debtLockers[loan][dlFactory]).claim();

        (uint256 poolDelegatePortion, uint256 stakeLockerPortion, uint256 principalClaim, uint256 interestClaim) = PoolLib.calculateClaimAndPortions(claimInfo, delegateFee, stakingFee);

        // Subtract outstanding principal by the principal claimed plus excess returned.
        // Considers possible `principalClaim` overflow if Liquidity Asset is transferred directly into the Loan.
        if (principalClaim <= principalOut) {
            principalOut = principalOut - principalClaim;
        } else {
            interestClaim  = interestClaim.add(principalClaim - principalOut);  // Distribute `principalClaim` overflow as interest to LPs.
            principalClaim = principalOut;                                      // Set `principalClaim` to `principalOut` so correct amount gets transferred.
            principalOut   = 0;                                                 // Set `principalOut` to zero to avoid subtraction overflow.
        }

        // Accounts for rounding error in StakeLocker / Pool Delegate / LiquidityLocker interest split.
        interestSum = interestSum.add(interestClaim);

        _transferLiquidityAsset(poolDelegate, poolDelegatePortion);  // Transfer the fee and portion of interest to the Pool Delegate.
        _transferLiquidityAsset(stakeLocker,  stakeLockerPortion);   // Transfer the portion of interest to the StakeLocker.

        // Transfer remaining claim (remaining interest + principal + excess + recovered) to the LiquidityLocker.
        // Dust will accrue in the Pool, but this ensures that state variables are in sync with the LiquidityLocker balance updates.
        // Not using `balanceOf` in case of external address transferring the Liquidity Asset directly into Pool.
        // Ensures that internal accounting is exactly reflective of balance change.
        _transferLiquidityAsset(liquidityLocker, principalClaim.add(interestClaim));

        // Handle default if defaultSuffered > 0.
        if (claimInfo[6] > 0) _handleDefault(loan, claimInfo[6]);

        // Update funds received for StakeLockerFDTs.
        IStakeLocker(stakeLocker).updateFundsReceived();

        // Update funds received for PoolFDTs.
        updateFundsReceived();

        _emitBalanceUpdatedEvent();
        emit BalanceUpdated(stakeLocker, address(liquidityAsset), liquidityAsset.balanceOf(stakeLocker));

        emit Claim(loan, interestClaim, principalClaim, claimInfo[3], stakeLockerPortion, poolDelegatePortion);
    }

    /**
        @dev   Handles if a claim has been made and there is a non-zero defaultSuffered amount. 
        @dev   It emits a `DefaultSuffered` event. 
        @param loan            The address of a Loan that has defaulted.
        @param defaultSuffered The losses suffered from default after liquidation.
     */
    function _handleDefault(address loan, uint256 defaultSuffered) internal {

        (uint256 bptsBurned, uint256 postBurnBptBal, uint256 liquidityAssetRecoveredFromBurn) = PoolLib.handleDefault(liquidityAsset, stakeLocker, stakeAsset, defaultSuffered);

        // If BPT burn is not enough to cover full default amount, pass on losses to LPs with PoolFDT loss accounting.
        if (defaultSuffered > liquidityAssetRecoveredFromBurn) {
            poolLosses = poolLosses.add(defaultSuffered - liquidityAssetRecoveredFromBurn);
            updateLossesReceived();
        }

        // Transfer Liquidity Asset from burn to LiquidityLocker.
        liquidityAsset.safeTransfer(liquidityLocker, liquidityAssetRecoveredFromBurn);

        principalOut = principalOut.sub(defaultSuffered);  // Subtract rest of the Loan's principal from `principalOut`.

        emit DefaultSuffered(
            loan,                            // The Loan that suffered the default.
            defaultSuffered,                 // Total default suffered from the Loan by the Pool after liquidation.
            bptsBurned,                      // Amount of BPTs burned from StakeLocker.
            postBurnBptBal,                  // Remaining BPTs in StakeLocker post-burn.
            liquidityAssetRecoveredFromBurn  // Amount of Liquidity Asset recovered from burning BPTs.
        );
    }

    function deactivate() external override {
        _isValidDelegateAndProtocolNotPaused();
        _isValidState(State.Finalized);
        PoolLib.validateDeactivation(_globals(superFactory), principalOut, address(liquidityAsset));
        poolState = State.Deactivated;
        emit PoolStateChanged(poolState);
    }

    /**************************************/
    /*** Pool Delegate Setter Functions ***/
    /**************************************/

    function setLiquidityCap(uint256 newLiquidityCap) external override {
        _whenProtocolNotPaused();
        _isValidDelegateOrPoolAdmin();
        liquidityCap = newLiquidityCap;
        emit LiquidityCapSet(newLiquidityCap);
    }

    function setLockupPeriod(uint256 newLockupPeriod) external override {
        _isValidDelegateAndProtocolNotPaused();
        require(newLockupPeriod <= lockupPeriod, "P:BAD_VALUE");
        lockupPeriod = newLockupPeriod;
        emit LockupPeriodSet(newLockupPeriod);
    }

    function setStakingFee(uint256 newStakingFee) external override {
        _isValidDelegateAndProtocolNotPaused();
        require(newStakingFee.add(delegateFee) <= 10_000, "P:BAD_FEE");
        stakingFee = newStakingFee;
        emit StakingFeeSet(newStakingFee);
    }

    function setAllowList(address account, bool status) external override {
        _isValidDelegateAndProtocolNotPaused();
        allowedLiquidityProviders[account] = status;
        emit LPStatusChanged(account, status);
    }

    function setPoolAdmin(address poolAdmin, bool allowed) external override {
        _isValidDelegateAndProtocolNotPaused();
        poolAdmins[poolAdmin] = allowed;
        emit PoolAdminSet(poolAdmin, allowed);
    }

    function setOpenToPublic(bool open) external override {
        _isValidDelegateAndProtocolNotPaused();
        openToPublic = open;
        emit PoolOpenedToPublic(open);
    }

    /************************************/
    /*** Liquidity Provider Functions ***/
    /************************************/

    function deposit(uint256 amt) external override {
        _whenProtocolNotPaused();
        _isValidState(State.Finalized);
        require(isDepositAllowed(amt), "P:DEP_NOT_ALLOWED");

        withdrawCooldown[msg.sender] = uint256(0);  // Reset the LP's withdraw cooldown if they had previously intended to withdraw.

        uint256 wad = _toWad(amt);
        PoolLib.updateDepositDate(depositDate, balanceOf(msg.sender), wad, msg.sender);

        liquidityAsset.safeTransferFrom(msg.sender, liquidityLocker, amt);
        _mint(msg.sender, wad);

        _emitBalanceUpdatedEvent();
        emit Cooldown(msg.sender, uint256(0));
    }

    function intendToWithdraw() external override {
        require(balanceOf(msg.sender) != uint256(0), "P:ZERO_BAL");
        withdrawCooldown[msg.sender] = block.timestamp;
        emit Cooldown(msg.sender, block.timestamp);
    }

    function cancelWithdraw() external override {
        require(withdrawCooldown[msg.sender] != uint256(0), "P:NOT_WITHDRAWING");
        withdrawCooldown[msg.sender] = uint256(0);
        emit Cooldown(msg.sender, uint256(0));
    }

    /**
        @dev   Checks that the account can withdraw an amount.
        @param account The address of the account.
        @param wad     The amount to withdraw.
     */
    function _canWithdraw(address account, uint256 wad) internal view {
        require(depositDate[account].add(lockupPeriod) <= block.timestamp,     "P:FUNDS_LOCKED");     // Restrict withdrawal during lockup period
        require(balanceOf(account).sub(wad) >= totalCustodyAllowance[account], "P:INSUF_TRANS_BAL");  // Account can only withdraw tokens that aren't custodied
    }

    function withdraw(uint256 amt) external override {
        _whenProtocolNotPaused();
        uint256 wad = _toWad(amt);
        (uint256 lpCooldownPeriod, uint256 lpWithdrawWindow) = _globals(superFactory).getLpCooldownParams();

        _canWithdraw(msg.sender, wad);
        require((block.timestamp - (withdrawCooldown[msg.sender] + lpCooldownPeriod)) <= lpWithdrawWindow, "P:WITHDRAW_NOT_ALLOWED");

        _burn(msg.sender, wad);  // Burn the corresponding PoolFDTs balance.
        withdrawFunds();         // Transfer full entitled interest, decrement `interestSum`.

        // Transfer amount that is due after realized losses are accounted for.
        // Recognized losses are absorbed by the LP.
        _transferLiquidityLockerFunds(msg.sender, amt.sub(_recognizeLosses()));

        _emitBalanceUpdatedEvent();
    }

    /**
        @dev   Transfers PoolFDTs.
        @param from Th address  sending   PoolFDTs.
        @param to   The address receiving PoolFDTs.
        @param wad  The amount of PoolFDTs to transfer.
     */
    function _transfer(address from, address to, uint256 wad) internal override {
        _whenProtocolNotPaused();

        (uint256 lpCooldownPeriod, uint256 lpWithdrawWindow) = _globals(superFactory).getLpCooldownParams();

        _canWithdraw(from, wad);
        require(block.timestamp > (withdrawCooldown[to] + lpCooldownPeriod + lpWithdrawWindow), "P:TO_NOT_ALLOWED");  // Recipient must not be currently withdrawing.
        require(recognizableLossesOf(from) == uint256(0),                                       "P:RECOG_LOSSES");    // If an LP has unrecognized losses, they must recognize losses using `withdraw`.

        PoolLib.updateDepositDate(depositDate, balanceOf(to), wad, to);
        super._transfer(from, to, wad);
    }

    function withdrawFunds() public override(IPool, IBasicFDT) {
        _whenProtocolNotPaused();
        uint256 withdrawableFunds = _prepareWithdraw();

        if (withdrawableFunds == uint256(0)) return;

        _transferLiquidityLockerFunds(msg.sender, withdrawableFunds);
        _emitBalanceUpdatedEvent();

        interestSum = interestSum.sub(withdrawableFunds);

        _updateFundsTokenBalance();
    }

    function increaseCustodyAllowance(address custodian, uint256 amount) external override {
        uint256 oldAllowance      = custodyAllowance[msg.sender][custodian];
        uint256 newAllowance      = oldAllowance.add(amount);
        uint256 newTotalAllowance = totalCustodyAllowance[msg.sender].add(amount);

        PoolLib.increaseCustodyAllowanceChecks(custodian, amount, newTotalAllowance, balanceOf(msg.sender));

        custodyAllowance[msg.sender][custodian] = newAllowance;
        totalCustodyAllowance[msg.sender]       = newTotalAllowance;
        emit CustodyAllowanceChanged(msg.sender, custodian, oldAllowance, newAllowance);
        emit TotalCustodyAllowanceUpdated(msg.sender, newTotalAllowance);
    }

    function transferByCustodian(address from, address to, uint256 amount) external override {
        uint256 oldAllowance = custodyAllowance[from][msg.sender];
        uint256 newAllowance = oldAllowance.sub(amount);

        PoolLib.transferByCustodianChecks(from, to, amount);

        custodyAllowance[from][msg.sender] = newAllowance;
        uint256 newTotalAllowance          = totalCustodyAllowance[from].sub(amount);
        totalCustodyAllowance[from]        = newTotalAllowance;
        emit CustodyTransfer(msg.sender, from, to, amount);
        emit CustodyAllowanceChanged(from, msg.sender, oldAllowance, newAllowance);
        emit TotalCustodyAllowanceUpdated(msg.sender, newTotalAllowance);
    }

    /**************************/
    /*** Governor Functions ***/
    /**************************/

    function reclaimERC20(address token) external override {
        PoolLib.reclaimERC20(token, address(liquidityAsset), _globals(superFactory));
    }

    /*************************/
    /*** Getter Functions ***/
    /*************************/

    function BPTVal(
        address _bPool,
        address _liquidityAsset,
        address _staker,
        address _stakeLocker
    ) external override view returns (uint256) {
        return PoolLib.BPTVal(_bPool, _liquidityAsset, _staker, _stakeLocker);
    }

    function isDepositAllowed(uint256 depositAmt) public override view returns (bool) {
        return (openToPublic || allowedLiquidityProviders[msg.sender]) &&
               _balanceOfLiquidityLocker().add(principalOut).add(depositAmt) <= liquidityCap;
    }

    function getInitialStakeRequirements() public override view returns (uint256, uint256, bool, uint256, uint256) {
        return PoolLib.getInitialStakeRequirements(_globals(superFactory), stakeAsset, address(liquidityAsset), poolDelegate, stakeLocker);
    }

    function getPoolSharesRequired(
        address _bPool,
        address _liquidityAsset,
        address _staker,
        address _stakeLocker,
        uint256 _liquidityAssetAmountRequired
    ) external override view returns (uint256, uint256) {
        return PoolLib.getPoolSharesRequired(_bPool, _liquidityAsset, _staker, _stakeLocker, _liquidityAssetAmountRequired);
    }

    function isPoolFinalized() external override view returns (bool) {
        return poolState == State.Finalized;
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    /**
        @dev   Converts to WAD precision.
        @param amt The amount to convert.
     */
    function _toWad(uint256 amt) internal view returns (uint256) {
        return amt.mul(WAD).div(10 ** liquidityAssetDecimals);
    }

    /**
        @dev    Returns the balance of this Pool's LiquidityLocker.
        @return The balance of LiquidityLocker.
     */
    function _balanceOfLiquidityLocker() internal view returns (uint256) {
        return liquidityAsset.balanceOf(liquidityLocker);
    }

    /**
        @dev   Checks that the current state of Pool matches the provided state.
        @param _state A Pool state.
     */
    function _isValidState(State _state) internal view {
        require(poolState == _state, "P:BAD_STATE");
    }

    /**
        @dev Checks that `msg.sender` is the Pool Delegate.
     */
    function _isValidDelegate() internal view {
        require(msg.sender == poolDelegate, "P:NOT_DEL");
    }

    /**
        @dev Returns the MapleGlobals instance.
     */
    function _globals(address poolFactory) internal view returns (IMapleGlobals) {
        return IMapleGlobals(IPoolFactory(poolFactory).globals());
    }

    /**
        @dev Emits a `BalanceUpdated` event for LiquidityLocker. 
        @dev It emits a `BalanceUpdated` event. 
     */
    function _emitBalanceUpdatedEvent() internal {
        emit BalanceUpdated(liquidityLocker, address(liquidityAsset), _balanceOfLiquidityLocker());
    }

    /**
        @dev   Transfers Liquidity Asset to given `to` address, from self (i.e. `address(this)`).
        @param to    The address to transfer liquidityAsset.
        @param value The amount of liquidity asset that gets transferred.
     */
    function _transferLiquidityAsset(address to, uint256 value) internal {
        liquidityAsset.safeTransfer(to, value);
    }

    /**
        @dev Checks that `msg.sender` is the Pool Delegate or a Pool Admin.
     */
    function _isValidDelegateOrPoolAdmin() internal view {
        require(msg.sender == poolDelegate || poolAdmins[msg.sender], "P:NOT_DEL_OR_ADMIN");
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
