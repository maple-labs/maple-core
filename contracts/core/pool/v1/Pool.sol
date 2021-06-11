// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/SafeERC20.sol";

import "libraries/pool/v1/PoolLib.sol";

import "core/debt-locker/v1/interfaces/IDebtLocker.sol";
import "core/globals/v1/interfaces/IMapleGlobals.sol";
import "core/liquidity-locker/v1/interfaces/ILiquidityLocker.sol";
import "core/liquidity-locker/v1/interfaces/ILiquidityLockerFactory.sol";
import "core/stake-locker/v1/interfaces/IStakeLocker.sol";
import "core/stake-locker/v1/interfaces/IStakeLockerFactory.sol";

import "./interfaces/IPoolFactory.sol";

import "./PoolFDT.sol";

/// @title Pool maintains all accounting and functionality related to Pools.
contract Pool is PoolFDT {

    using SafeMath  for uint256;
    using SafeERC20 for IERC20;

    uint256 constant WAD = 10 ** 18;

    uint8 public constant DL_FACTORY = 1;  // Factory type of `DebtLockerFactory`.

    IERC20  public immutable liquidityAsset;  // The asset deposited by Lenders into the LiquidityLocker, for funding Loans.

    address public immutable poolDelegate;     // The Pool Delegate address, maintains full authority over the Pool.
    address public immutable liquidityLocker;  // The LiquidityLocker owned by this contract
    address public immutable stakeAsset;       // The address of the asset deposited by Stakers into the StakeLocker (BPTs), for liquidation during default events.
    address public immutable stakeLocker;      // The address of the StakeLocker, escrowing `stakeAsset`.
    address public immutable superFactory;     // The factory that deployed this Loan.

    uint256 private immutable liquidityAssetDecimals;  // The precision for the Liquidity Asset (i.e. `decimals()`).

    uint256 public           stakingFee;   // The fee Stakers earn            (in basis points).
    uint256 public immutable delegateFee;  // The fee the Pool Delegate earns (in basis points).

    uint256 public principalOut;  // The sum of all outstanding principal on Loans.
    uint256 public liquidityCap;  // The amount of liquidity tokens accepted by the Pool.
    uint256 public lockupPeriod;  // The period of time from an account's deposit date during which they cannot withdraw any funds.

    bool public openToPublic;  // Boolean opening Pool to public for LP deposits

    enum State { Initialized, Finalized, Deactivated }
    State public poolState;

    mapping(address => uint256)                     public depositDate;                // Used for withdraw penalty calculation.
    mapping(address => mapping(address => address)) public debtLockers;                // Address of the DebtLocker corresponding to `[Loan][DebtLockerFactory]`.
    mapping(address => bool)                        public poolAdmins;                 // The Pool Admin addresses that have permission to do certain operations in case of disaster management.
    mapping(address => bool)                        public allowedLiquidityProviders;  // Mapping that contains the list of addresses that have early access to the pool.
    mapping(address => uint256)                     public withdrawCooldown;           // The timestamp of when individual LPs have notified of their intent to withdraw.
    mapping(address => mapping(address => uint256)) public custodyAllowance;           // The amount of PoolFDTs that are "locked" at a certain address.
    mapping(address => uint256)                     public totalCustodyAllowance;      // The total amount of PoolFDTs that are "locked" for a given account. Cannot be greater than an account's balance.

    event                   LoanFunded(address indexed loan, address debtLocker, uint256 amountFunded);
    event                        Claim(address indexed loan, uint256 interest, uint256 principal, uint256 fee, uint256 stakeLockerPortion, uint256 poolDelegatePortion);
    event               BalanceUpdated(address indexed liquidityProvider, address indexed token, uint256 balance);
    event              CustodyTransfer(address indexed custodian, address indexed from, address indexed to, uint256 amount);
    event      CustodyAllowanceChanged(address indexed liquidityProvider, address indexed custodian, uint256 oldAllowance, uint256 newAllowance);
    event              LPStatusChanged(address indexed liquidityProvider, bool status);
    event              LiquidityCapSet(uint256 newLiquidityCap);
    event              LockupPeriodSet(uint256 newLockupPeriod);
    event                StakingFeeSet(uint256 newStakingFee);
    event             PoolStateChanged(State state);
    event                     Cooldown(address indexed liquidityProvider, uint256 cooldown);
    event           PoolOpenedToPublic(bool isOpen);
    event                 PoolAdminSet(address indexed poolAdmin, bool allowed);
    event           DepositDateUpdated(address indexed liquidityProvider, uint256 depositDate);
    event TotalCustodyAllowanceUpdated(address indexed liquidityProvider, uint256 newTotalAllowance);

    event DefaultSuffered(
        address indexed loan,
        uint256 defaultSuffered,
        uint256 bptsBurned,
        uint256 bptsReturned,
        uint256 liquidityAssetRecoveredFromBurn
    );

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

    /**
        @dev Finalizes the Pool, enabling deposits. Checks the amount the Pool Delegate deposited to the StakeLocker.
             Only the Pool Delegate can call this function.
        @dev It emits a `PoolStateChanged` event.
    */
    function finalize() external {
        _isValidDelegateAndProtocolNotPaused();
        _isValidState(State.Initialized);
        (,, bool stakeSufficient,,) = getInitialStakeRequirements();
        require(stakeSufficient, "P:INSUF_STAKE");
        poolState = State.Finalized;
        emit PoolStateChanged(poolState);
    }

    /**
        @dev   Funds a Loan for an amount, utilizing the supplied DebtLockerFactory for DebtLockers.
               Only the Pool Delegate can call this function.
        @dev   It emits a `LoanFunded` event.
        @dev   It emits a `BalanceUpdated` event.
        @param loan      Address of the Loan to fund.
        @param dlFactory Address of the DebtLockerFactory to utilize.
        @param amt       Amount to fund the Loan.
    */
    function fundLoan(address loan, address dlFactory, uint256 amt) external {
        _isValidDelegateAndProtocolNotPaused();
        _isValidState(State.Finalized);
        principalOut = principalOut.add(amt);
        PoolLib.fundLoan(debtLockers, superFactory, liquidityLocker, loan, dlFactory, amt);
        _emitBalanceUpdatedEvent();
    }

    /**
        @dev   Liquidates a Loan. The Pool Delegate could liquidate the Loan only when the Loan completes its grace period.
               The Pool Delegate can claim its proportion of recovered funds from the liquidation using the `claim()` function.
               Only the Pool Delegate can call this function.
        @param loan      Address of the Loan to liquidate.
        @param dlFactory Address of the DebtLockerFactory that is used to pull corresponding DebtLocker.
    */
    function triggerDefault(address loan, address dlFactory) external {
        _isValidDelegateAndProtocolNotPaused();
        IDebtLocker(debtLockers[loan][dlFactory]).triggerDefault();
    }

    /**
        @dev    Claims available funds for the Loan through a specified DebtLockerFactory. Only the Pool Delegate or a Pool Admin can call this function.
        @dev    It emits two `BalanceUpdated` events.
        @dev    It emits a `Claim` event.
        @param  loan      Address of the loan to claim from.
        @param  dlFactory Address of the DebtLockerFactory.
        @return claimInfo The claim details.
                    claimInfo [0] = Total amount claimed
                    claimInfo [1] = Interest  portion claimed
                    claimInfo [2] = Principal portion claimed
                    claimInfo [3] = Fee       portion claimed
                    claimInfo [4] = Excess    portion claimed
                    claimInfo [5] = Recovered portion claimed (from liquidations)
                    claimInfo [6] = Default suffered
    */
    function claim(address loan, address dlFactory) external returns (uint256[7] memory claimInfo) {
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
        @param loan            Address of a Loan that has defaulted.
        @param defaultSuffered Losses suffered from default after liquidation.
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

    /**
        @dev Triggers deactivation, permanently shutting down the Pool. Must have less than 100 USD worth of Liquidity Asset `principalOut`.
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
        @dev   Sets the liquidity cap. Only the Pool Delegate or a Pool Admin can call this function.
        @dev   It emits a `LiquidityCapSet` event.
        @param newLiquidityCap New liquidity cap value.
    */
    function setLiquidityCap(uint256 newLiquidityCap) external {
        _whenProtocolNotPaused();
        _isValidDelegateOrPoolAdmin();
        liquidityCap = newLiquidityCap;
        emit LiquidityCapSet(newLiquidityCap);
    }

    /**
        @dev   Sets the lockup period. Only the Pool Delegate can call this function.
        @dev   It emits a `LockupPeriodSet` event.
        @param newLockupPeriod New lockup period used to restrict the withdrawals.
    */
    function setLockupPeriod(uint256 newLockupPeriod) external {
        _isValidDelegateAndProtocolNotPaused();
        require(newLockupPeriod <= lockupPeriod, "P:BAD_VALUE");
        lockupPeriod = newLockupPeriod;
        emit LockupPeriodSet(newLockupPeriod);
    }

    /**
        @dev   Sets the staking fee. Only the Pool Delegate can call this function.
        @dev   It emits a `StakingFeeSet` event.
        @param newStakingFee New staking fee.
    */
    function setStakingFee(uint256 newStakingFee) external {
        _isValidDelegateAndProtocolNotPaused();
        require(newStakingFee.add(delegateFee) <= 10_000, "P:BAD_FEE");
        stakingFee = newStakingFee;
        emit StakingFeeSet(newStakingFee);
    }

    /**
        @dev   Sets the account status in the Pool's allowlist. Only the Pool Delegate can call this function.
        @dev   It emits an `LPStatusChanged` event.
        @param account The address to set status for.
        @param status  The status of an account in the allowlist.
    */
    function setAllowList(address account, bool status) external {
        _isValidDelegateAndProtocolNotPaused();
        allowedLiquidityProviders[account] = status;
        emit LPStatusChanged(account, status);
    }

    /**
        @dev   Sets a Pool Admin. Only the Pool Delegate can call this function.
        @dev   It emits a `PoolAdminSet` event.
        @param poolAdmin An address being allowed or disallowed as a Pool Admin.
        @param allowed Status of a Pool Admin.
    */
    function setPoolAdmin(address poolAdmin, bool allowed) external {
        _isValidDelegateAndProtocolNotPaused();
        poolAdmins[poolAdmin] = allowed;
        emit PoolAdminSet(poolAdmin, allowed);
    }

    /**
        @dev   Sets whether the Pool is open to the public. Only the Pool Delegate can call this function.
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
        @dev   Handles Liquidity Providers depositing of Liquidity Asset into the LiquidityLocker, minting PoolFDTs.
        @dev   It emits a `DepositDateUpdated` event.
        @dev   It emits a `BalanceUpdated` event.
        @dev   It emits a `Cooldown` event.
        @param amt Amount of Liquidity Asset to deposit.
    */
    function deposit(uint256 amt) external {
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

    /**
        @dev Activates the cooldown period to withdraw. It can't be called if the account is not providing liquidity.
        @dev It emits a `Cooldown` event.
    **/
    function intendToWithdraw() external {
        require(balanceOf(msg.sender) != uint256(0), "P:ZERO_BAL");
        withdrawCooldown[msg.sender] = block.timestamp;
        emit Cooldown(msg.sender, block.timestamp);
    }

    /**
        @dev Cancels an initiated withdrawal by resetting the account's withdraw cooldown.
        @dev It emits a `Cooldown` event.
    **/
    function cancelWithdraw() external {
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

    /**
        @dev   Handles Liquidity Providers withdrawing of Liquidity Asset from the LiquidityLocker, burning PoolFDTs.
        @dev   It emits two `BalanceUpdated` event.
        @param amt Amount of Liquidity Asset to withdraw.
    */
    function withdraw(uint256 amt) external {
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
        @param from Address sending   PoolFDTs.
        @param to   Address receiving PoolFDTs.
        @param wad  Amount of PoolFDTs to transfer.
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

    /**
        @dev Withdraws all claimable interest from the LiquidityLocker for an account using `interestSum` accounting.
        @dev It emits a `BalanceUpdated` event.
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
        @dev   Increases the custody allowance for a given Custodian corresponding to the calling account (`msg.sender`).
        @dev   It emits a `CustodyAllowanceChanged` event.
        @dev   It emits a `TotalCustodyAllowanceUpdated` event.
        @param custodian Address which will act as Custodian of a given amount for an account.
        @param amount    Number of additional FDTs to be custodied by the Custodian.
    */
    function increaseCustodyAllowance(address custodian, uint256 amount) external {
        uint256 oldAllowance      = custodyAllowance[msg.sender][custodian];
        uint256 newAllowance      = oldAllowance.add(amount);
        uint256 newTotalAllowance = totalCustodyAllowance[msg.sender].add(amount);

        PoolLib.increaseCustodyAllowanceChecks(custodian, amount, newTotalAllowance, balanceOf(msg.sender));

        custodyAllowance[msg.sender][custodian] = newAllowance;
        totalCustodyAllowance[msg.sender]       = newTotalAllowance;
        emit CustodyAllowanceChanged(msg.sender, custodian, oldAllowance, newAllowance);
        emit TotalCustodyAllowanceUpdated(msg.sender, newTotalAllowance);
    }

    /**
        @dev   Transfers custodied PoolFDTs back to the account.
        @dev   `from` and `to` should always be equal in this implementation.
        @dev   This means that the Custodian can only decrease their own allowance and unlock funds for the original owner.
        @dev   It emits a `CustodyTransfer` event.
        @dev   It emits a `CustodyAllowanceChanged` event.
        @dev   It emits a `TotalCustodyAllowanceUpdated` event.
        @param from   Address which holds the PoolFDTs.
        @param to     Address which will be the new owner of the amount of PoolFDTs.
        @param amount Amount of PoolFDTs transferred.
    */
    function transferByCustodian(address from, address to, uint256 amount) external {
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

    /**
        @dev   Transfers any locked funds to the Governor. Only the Governor can call this function.
        @param token Address of the token to be reclaimed.
    */
    function reclaimERC20(address token) external {
        PoolLib.reclaimERC20(token, address(liquidityAsset), _globals(superFactory));
    }

    /*************************/
    /*** Getter Functions ***/
    /*************************/

    /**
        @dev    Calculates the value of BPT in units of Liquidity Asset.
        @param  _bPool          Address of Balancer pool.
        @param  _liquidityAsset Asset used by Pool for liquidity to fund Loans.
        @param  _staker         Address that deposited BPTs to StakeLocker.
        @param  _stakeLocker    Escrows BPTs deposited by Staker.
        @return USDC value of staker BPTs.
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
        @dev   Checks that the given deposit amount is acceptable based on current liquidityCap.
        @param depositAmt Amount of tokens (i.e liquidityAsset type) the account is trying to deposit.
    */
    function isDepositAllowed(uint256 depositAmt) public view returns (bool) {
        return (openToPublic || allowedLiquidityProviders[msg.sender]) &&
               _balanceOfLiquidityLocker().add(principalOut).add(depositAmt) <= liquidityCap;
    }

    /**
        @dev    Returns information on the stake requirements.
        @return [0] = Min amount of Liquidity Asset coverage from staking required.
                [1] = Present amount of Liquidity Asset coverage from the Pool Delegate stake.
                [2] = If enough stake is present from the Pool Delegate for finalization.
                [3] = Staked BPTs required for minimum Liquidity Asset coverage.
                [4] = Current staked BPTs.
    */
    function getInitialStakeRequirements() public view returns (uint256, uint256, bool, uint256, uint256) {
        return PoolLib.getInitialStakeRequirements(_globals(superFactory), stakeAsset, address(liquidityAsset), poolDelegate, stakeLocker);
    }

    /**
        @dev    Calculates BPTs required if burning BPTs for the Liquidity Asset, given supplied `tokenAmountOutRequired`.
        @param  _bPool                        The Balancer pool that issues the BPTs.
        @param  _liquidityAsset               Swap out asset (e.g. USDC) to receive when burning BPTs.
        @param  _staker                       Address that deposited BPTs to StakeLocker.
        @param  _stakeLocker                  Escrows BPTs deposited by Staker.
        @param  _liquidityAssetAmountRequired Amount of Liquidity Asset required to recover.
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
    function isPoolFinalized() external view returns (bool) {
        return poolState == State.Finalized;
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    /**
        @dev   Converts to WAD precision.
        @param amt Amount to convert.
    */
    function _toWad(uint256 amt) internal view returns (uint256) {
        return amt.mul(WAD).div(10 ** liquidityAssetDecimals);
    }

    /**
        @dev    Returns the balance of this Pool's LiquidityLocker.
        @return Balance of LiquidityLocker.
    */
    function _balanceOfLiquidityLocker() internal view returns (uint256) {
        return liquidityAsset.balanceOf(liquidityLocker);
    }

    /**
        @dev   Checks that the current state of Pool matches the provided state.
        @param _state Enum of desired Pool state.
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
