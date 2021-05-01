// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/SafeERC20.sol";
import "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";

import "./interfaces/IMapleGlobals.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IPoolFactory.sol";

import "./token/StakeLockerFDT.sol";

/// @title StakeLocker holds custody of stakeAsset tokens for a given Pool and earns revenue from interest.
contract StakeLocker is StakeLockerFDT, Pausable {

    using SafeMathInt    for int256;
    using SignedSafeMath for int256;
    using SafeERC20      for IERC20;

    uint256 constant WAD = 10 ** 18;  // Scaling factor for synthetic float division.

    IERC20  public immutable stakeAsset;  // The asset deposited by Stakers into this contract, for liquidation during defaults.

    address public immutable liquidityAsset;  // The Liquidity Asset for the Pool as well as the dividend token for StakeLockerFDT interest.
    address public immutable pool;            // The parent Pool.

    uint256 public lockupPeriod;  // Number of seconds for which unstaking is not allowed.

    mapping(address => uint256)                     public stakeDate;              // Map of account addresses to effective stake date.
    mapping(address => uint256)                     public unstakeCooldown;        // The timestamp of when a Staker called `cooldown()`.
    mapping(address => bool)                        public allowed;                // Map of addresses to allowed status.
    mapping(address => mapping(address => uint256)) public custodyAllowance;       // Amount of StakeLockerFDTs that are "locked" at a certain address.
    mapping(address => uint256)                     public totalCustodyAllowance;  // Total amount of StakeLockerFDTs that are "locked" for a given account, cannot be greater than balance.

    bool public openToPublic;  // Boolean opening StakeLocker to public for staking BPTs

    event            StakeLockerOpened();
    event               BalanceUpdated(address indexed staker, address indexed token, uint256 balance);
    event             AllowListUpdated(address indexed staker, bool status);
    event             StakeDateUpdated(address indexed staker, uint256 stakeDate);
    event          LockupPeriodUpdated(uint256 lockupPeriod);
    event                     Cooldown(address indexed staker, uint256 cooldown);
    event                        Stake(address indexed staker, uint256 amount);
    event                      Unstake(address indexed staker, uint256 amount);
    event              CustodyTransfer(address indexed custodian, address indexed from, address indexed to, uint256 amount);
    event      CustodyAllowanceChanged(address indexed staker, address indexed custodian, uint256 oldAllowance, uint256 newAllowance);
    event TotalCustodyAllowanceUpdated(address indexed staker, uint256 newTotalAllowance);

    constructor(
        address _stakeAsset,
        address _liquidityAsset,
        address _pool
    ) StakeLockerFDT("Maple StakeLocker", "MPLSTAKE", _liquidityAsset) public {
        liquidityAsset = _liquidityAsset;
        stakeAsset     = IERC20(_stakeAsset);
        pool           = _pool;
        lockupPeriod   = 180 days;
    }

    /*****************/
    /*** Modifiers ***/
    /*****************/

    /**
        @dev Checks that an account can unstake given the following conditions:
                 1. The Account is not the Pool Delegate and the Pool is in Finalized state.
                 2. The Pool is in Initialized or Deactivated state.
    */
    modifier canUnstake(address from) {
        IPool _pool = IPool(pool);

        // The Pool cannot be finalized, but if it is, account cannot be the Pool Delegate.
        require(!_pool.isPoolFinalized() || from != _pool.poolDelegate(), "SL:STAKE_LOCKED");
        _;
    }

    /**
        @dev Checks that `msg.sender` is the Governor.
    */
    modifier isGovernor() {
        require(msg.sender == _globals().governor(), "SL:NOT_GOV");
        _;
    }

    /**
        @dev Checks that `msg.sender` is the Pool.
    */
    modifier isPool() {
        require(msg.sender == pool, "SL:NOT_P");
        _;
    }

    /**********************/
    /*** Pool Functions ***/
    /**********************/

    /**
        @dev   Updates Staker status on the allowlist. Only the Pool Delegate can call this function.
        @dev   It emits an `AllowListUpdated` event.
        @param staker The address of the Staker to set status for.
        @param status The status of the Staker on allowlist.
    */
    function setAllowlist(address staker, bool status) public {
        _whenProtocolNotPaused();
        _isValidPoolDelegate();
        allowed[staker] = status;
        emit AllowListUpdated(staker, status);
    }

    /**
        @dev Sets the StakeLocker as open to the public. Only the Pool Delegate can call this function.
        @dev It emits a `StakeLockerOpened` event.
    */
    function openStakeLockerToPublic() external {
        _whenProtocolNotPaused();
        _isValidPoolDelegate();
        openToPublic = true;
        emit StakeLockerOpened();
    }

    /**
        @dev   Sets the lockup period. Only the Pool Delegate can call this function.
        @dev   It emits a `LockupPeriodUpdated` event.
        @param newLockupPeriod New lockup period used to restrict unstaking.
    */
    function setLockupPeriod(uint256 newLockupPeriod) external {
        _whenProtocolNotPaused();
        _isValidPoolDelegate();
        require(newLockupPeriod <= lockupPeriod, "SL:INVALID_VALUE");
        lockupPeriod = newLockupPeriod;
        emit LockupPeriodUpdated(newLockupPeriod);
    }

    /**
        @dev   Transfers an amount of Stake Asset to a destination account. Only the Pool can call this function.
        @param dst Destination to transfer Stake Asset to.
        @param amt Amount of Stake Asset to transfer.
    */
    function pull(address dst, uint256 amt) isPool external {
        stakeAsset.safeTransfer(dst, amt);
    }

    /**
        @dev   Updates loss accounting for StakeLockerFDTs after BPTs have been burned. Only the Pool can call this function.
        @param bptsBurned Amount of BPTs that have been burned.
    */
    function updateLosses(uint256 bptsBurned) isPool external {
        bptLosses = bptLosses.add(bptsBurned);
        updateLossesReceived();
    }

    /************************/
    /*** Staker Functions ***/
    /************************/

    /**
        @dev   Handles a Staker's depositing of an amount of Stake Asset, minting them StakeLockerFDTs.
        @dev   It emits a `StakeDateUpdated` event.
        @dev   It emits a `Stake` event.
        @dev   It emits a `Cooldown` event.
        @dev   It emits a `BalanceUpdated` event.
        @param amt Amount of Stake Asset (BPTs) to deposit.
    */
    function stake(uint256 amt) whenNotPaused external {
        _whenProtocolNotPaused();
        _isAllowed(msg.sender);

        unstakeCooldown[msg.sender] = uint256(0);  // Reset account's unstake cooldown if Staker had previously intended to unstake.

        _updateStakeDate(msg.sender, amt);

        stakeAsset.safeTransferFrom(msg.sender, address(this), amt);
        _mint(msg.sender, amt);

        emit Stake(msg.sender, amt);
        emit Cooldown(msg.sender, uint256(0));
        emit BalanceUpdated(address(this), address(stakeAsset), stakeAsset.balanceOf(address(this)));
    }

    /**
        @dev   Updates information used to calculate unstake delay.
        @dev   It emits a `StakeDateUpdated` event.
        @param account The Staker that deposited BPTs.
        @param amt     Amount of BPTs the Staker has deposited.
    */
    function _updateStakeDate(address account, uint256 amt) internal {
        uint256 prevDate = stakeDate[account];
        uint256 balance = balanceOf(account);

        // stakeDate + (now - stakeDate) * (amt / (balance + amt))
        // NOTE: prevDate = 0 implies balance = 0, and equation reduces to now.
        uint256 newDate = (balance + amt) > 0
            ? prevDate.add(block.timestamp.sub(prevDate).mul(amt).div(balance + amt))
            : prevDate;

        stakeDate[account] = newDate;
        emit StakeDateUpdated(account, newDate);
    }

    /**
        @dev Activates the cooldown period to unstake. It can't be called if the account is not staking.
        @dev It emits a `Cooldown` event.
    **/
    function intendToUnstake() external {
        require(balanceOf(msg.sender) != uint256(0), "SL:ZERO_BALANCE");
        unstakeCooldown[msg.sender] = block.timestamp;
        emit Cooldown(msg.sender, block.timestamp);
    }

    /**
        @dev Cancels an initiated unstake by resetting the calling account's unstake cooldown.
        @dev It emits a `Cooldown` event.
    */
    function cancelUnstake() external {
        require(unstakeCooldown[msg.sender] != uint256(0), "SL:NOT_UNSTAKING");
        unstakeCooldown[msg.sender] = 0;
        emit Cooldown(msg.sender, uint256(0));
    }

    /**
        @dev   Handles a Staker's withdrawing of an amount of Stake Asset, minus any losses. It also claims interest and burns StakeLockerFDTs for the calling account.
        @dev   It emits an `Unstake` event.
        @dev   It emits a `BalanceUpdated` event.
        @param amt Amount of Stake Asset (BPTs) to withdraw.
    */
    function unstake(uint256 amt) external canUnstake(msg.sender) {
        _whenProtocolNotPaused();

        require(balanceOf(msg.sender).sub(amt) >= totalCustodyAllowance[msg.sender], "SL:INSUF_UNSTAKEABLE_BAL");  // Account can only unstake tokens that aren't custodied
        require(isUnstakeAllowed(msg.sender),                                        "SL:OUTSIDE_COOLDOWN");
        require(stakeDate[msg.sender].add(lockupPeriod) <= block.timestamp,          "SL:FUNDS_LOCKED");

        updateFundsReceived();   // Account for any funds transferred into contract since last call.
        _burn(msg.sender, amt);  // Burn the corresponding StakeLockerFDTs balance.
        withdrawFunds();         // Transfer the full entitled Liquidity Asset interest.

        stakeAsset.safeTransfer(msg.sender, amt.sub(_recognizeLosses()));  // Unstake amount minus losses.

        emit Unstake(msg.sender, amt);
        emit BalanceUpdated(address(this), address(stakeAsset), stakeAsset.balanceOf(address(this)));
    }

    /**
        @dev Withdraws all claimable interest earned from the StakeLocker for an account.
        @dev It emits a `BalanceUpdated` event if there are withdrawable funds.
    */
    function withdrawFunds() public override {
        _whenProtocolNotPaused();

        uint256 withdrawableFunds = _prepareWithdraw();

        if (withdrawableFunds == uint256(0)) return;

        fundsToken.safeTransfer(msg.sender, withdrawableFunds);
        emit BalanceUpdated(address(this), address(fundsToken), fundsToken.balanceOf(address(this)));

        _updateFundsTokenBalance();
    }

    /**
        @dev   Increases the custody allowance for a given Custodian corresponding to the account (`msg.sender`).
        @dev   It emits a `CustodyAllowanceChanged` event.
        @dev   It emits a `TotalCustodyAllowanceUpdated` event.
        @param custodian Address which will act as Custodian of a given amount for an account.
        @param amount    Number of additional FDTs to be custodied by the Custodian.
    */
    function increaseCustodyAllowance(address custodian, uint256 amount) external {
        uint256 oldAllowance      = custodyAllowance[msg.sender][custodian];
        uint256 newAllowance      = oldAllowance.add(amount);
        uint256 newTotalAllowance = totalCustodyAllowance[msg.sender].add(amount);

        require(custodian != address(0),                    "SL:INVALID_CUSTODIAN");
        require(amount    != uint256(0),                    "SL:INVALID_AMT");
        require(newTotalAllowance <= balanceOf(msg.sender), "SL:INSUF_BALANCE");

        custodyAllowance[msg.sender][custodian] = newAllowance;
        totalCustodyAllowance[msg.sender]       = newTotalAllowance;
        emit CustodyAllowanceChanged(msg.sender, custodian, oldAllowance, newAllowance);
        emit TotalCustodyAllowanceUpdated(msg.sender, newTotalAllowance);
    }

    /**
        @dev   Transfers custodied StakeLockerFDTs back to the account.
        @dev   `from` and `to` should always be equal in this implementation.
        @dev   This means that the Custodian can only decrease their own allowance and unlock funds for the original owner.
        @dev   It emits a `CustodyTransfer` event.
        @dev   It emits a `CustodyAllowanceChanged` event.
        @dev   It emits a `TotalCustodyAllowanceUpdated` event.
        @param from   Address which holds the StakeLockerFDTs.
        @param to     Address which will be the new owner of the amount of StakeLockerFDTs.
        @param amount Amount of StakeLockerFDTs transferred.
    */
    function transferByCustodian(address from, address to, uint256 amount) external {
        uint256 oldAllowance = custodyAllowance[from][msg.sender];
        uint256 newAllowance = oldAllowance.sub(amount);

        require(to == from,             "SL:INVALID_RECEIVER");
        require(amount != uint256(0),   "SL:INVALID_AMT");

        custodyAllowance[from][msg.sender] = newAllowance;
        uint256 newTotalAllowance          = totalCustodyAllowance[from].sub(amount);
        totalCustodyAllowance[from]        = newTotalAllowance;
        emit CustodyTransfer(msg.sender, from, to, amount);
        emit CustodyAllowanceChanged(from, msg.sender, oldAllowance, newAllowance);
        emit TotalCustodyAllowanceUpdated(msg.sender, newTotalAllowance);
    }

    /**
        @dev   Transfers StakeLockerFDTs.
        @param from Address sending   StakeLockerFDTs.
        @param to   Address receiving StakeLockerFDTs.
        @param wad  Amount of StakeLockerFDTs to transfer.
    */
    function _transfer(address from, address to, uint256 wad) internal override canUnstake(from) {
        _whenProtocolNotPaused();
        require(stakeDate[from].add(lockupPeriod) <= block.timestamp,    "SL:FUNDS_LOCKED");            // Restrict withdrawal during lockup period
        require(balanceOf(from).sub(wad) >= totalCustodyAllowance[from], "SL:INSUF_TRANSFERABLE_BAL");  // Account can only transfer tokens that aren't custodied
        require(isReceiveAllowed(unstakeCooldown[to]),                   "SL:RECIPIENT_NOT_ALLOWED");   // Recipient must not be currently unstaking
        require(recognizableLossesOf(from) == uint256(0),                "SL:RECOG_LOSSES");            // If a staker has unrecognized losses, they must recognize losses through unstake
        _updateStakeDate(to, wad);                                                                      // Update stake date of recipient
        super._transfer(from, to, wad);
    }

    /***********************/
    /*** Admin Functions ***/
    /***********************/

    /**
        @dev Triggers paused state. Halts functionality for certain functions. Only the Pool Delegate or a Pool Admin can call this function.
    */
    function pause() external {
        _isValidPoolDelegateOrPoolAdmin();
        super._pause();
    }

    /**
        @dev Triggers unpaused state. Restores functionality for certain functions. Only the Pool Delegate or a Pool Admin can call this function.
    */
    function unpause() external {
        _isValidPoolDelegateOrPoolAdmin();
        super._unpause();
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    /**
        @dev Returns if the unstake cooldown period has passed for `msg.sender` and if they are in the unstake window.
    */
    function isUnstakeAllowed(address from) public view returns (bool) {
        IMapleGlobals globals = _globals();
        return (block.timestamp - (unstakeCooldown[from] + globals.stakerCooldownPeriod())) <= globals.stakerUnstakeWindow();
    }

    /**
        @dev Returns if an account is allowed to receive a transfer.
             This is only possible if they have zero cooldown or they are past their unstake window.
    */
    function isReceiveAllowed(uint256 _unstakeCooldown) public view returns (bool) {
        IMapleGlobals globals = _globals();
        return block.timestamp > (_unstakeCooldown + globals.stakerCooldownPeriod() + globals.stakerUnstakeWindow());
    }

    /**
        @dev Checks that `msg.sender` is the Pool Delegate or a Pool Admin.
    */
    function _isValidPoolDelegateOrPoolAdmin() internal view {
        require(msg.sender == IPool(pool).poolDelegate() || IPool(pool).poolAdmins(msg.sender), "SL:NOT_DELEGATE_OR_ADMIN");
    }

    /**
        @dev Checks that `msg.sender` is the Pool Delegate.
    */
    function _isValidPoolDelegate() internal view {
        require(msg.sender == IPool(pool).poolDelegate(), "SL:NOT_DELEGATE");
    }

    /**
        @dev Checks that `msg.sender` is allowed to stake.
    */
    function _isAllowed(address account) internal view {
        require(
            openToPublic || allowed[account] || account == IPool(pool).poolDelegate(),
            "SL:NOT_ALLOWED"
        );
    }

    /**
        @dev Returns the MapleGlobals instance.
    */
    function _globals() internal view returns (IMapleGlobals) {
        return IMapleGlobals(IPoolFactory(IPool(pool).superFactory()).globals());
    }

    /**
        @dev Checks that the protocol is not in a paused state.
    */
    function _whenProtocolNotPaused() internal view {
        require(!_globals().protocolPaused(), "SL:PROTO_PAUSED");
    }

}
