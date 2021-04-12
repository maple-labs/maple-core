// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "./interfaces/IGlobals.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IPoolFactory.sol";

import "./token/StakeLockerFDT.sol";

import "lib/openzeppelin-contracts/contracts/token/ERC20/SafeERC20.sol";
import "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";

/// @title StakeLocker holds custody of stakeAsset tokens for a given Pool and earns revenue from interest.
contract StakeLocker is StakeLockerFDT, Pausable {

    using SafeMathInt    for int256;
    using SignedSafeMath for int256;
    using SafeERC20      for IERC20;

    uint256 constant WAD = 10 ** 18;  // Scaling factor for synthetic float division

    IERC20  public immutable stakeAsset;  // The asset deposited by stakers into this contract, for liquidation during defaults.

    address public immutable liquidityAsset;  // The liquidityAsset for the Pool as well as the dividend token for FDT interest.
    address public immutable pool;            // The parent liquidity pool.

    uint256 public lockupPeriod;  // Number of seconds for which unstaking is not allowed.

    mapping(address => uint256) public stakeDate;        // Map address to effective stake date value
    mapping(address => uint256) public unstakeCooldown;  // Timestamp of when staker called cooldown()
    mapping(address => bool)    public allowed;          // Map address to allowed status

    bool public openToPublic;  // Boolean opening StakeLocker to public for staking BPTs

    event   BalanceUpdated(address who, address token, uint256 balance);
    event AllowListUpdated(address staker, bool status);
    event StakeDateUpdated(address staker, uint256 stakeDate);
    event         Cooldown(address indexed staker, uint256 cooldown);
    event            Stake(uint256 amount, address staker);
    event          Unstake(uint256 amount, address staker);
    event StakeLockerOpened();

    constructor(
        address _stakeAsset,
        address _liquidityAsset,
        address _pool
    ) StakeLockerFDT("Maple Stake Locker", "MPLSTAKE", _liquidityAsset) public {
        liquidityAsset = _liquidityAsset;
        stakeAsset     = IERC20(_stakeAsset);
        pool           = _pool;
        lockupPeriod   = 180 days; // TODO: Confirm default
    }

    /*****************/
    /*** Modifiers ***/
    /*****************/

    /**
        @dev canUnstake enables unstaking in the following conditions:
        1. User is not Pool Delegate and the Pool is in Finalized state.
        2. The Pool is in Initialized or Deactivated state.
    */
    modifier canUnstake() {
        require(
            (msg.sender != IPool(pool).poolDelegate() && IPool(pool).isPoolFinalized()) ||
            !IPool(pool).isPoolFinalized(),
            "StakeLocker:ERR_STAKE_LOCKED"
        );
        _;
    }

    /**
        @dev Modifier to check if msg.sender is Governor.
    */
    modifier isGovernor() {
        require(msg.sender == _globals().governor(), "StakeLocker:MSG_SENDER_NOT_GOVERNOR");
        _;
    }

    /**
        @dev Modifier to check if msg.sender is Pool.
    */
    modifier isPool() {
        require(msg.sender == pool, "StakeLocker:MSG_SENDER_NOT_POOL");
        _;
    }

    /**********************/
    /*** Pool Functions ***/
    /**********************/

    /**
        @dev Update user status on the allowlist. Only Pool can call this.
        @param user   The address to set status for
        @param status The status of user on allowlist
    */
    function setAllowlist(address user, bool status) isPool public {
        allowed[user] = status;
        emit AllowListUpdated(user, status);
    }

    /**
        @dev Set StakerLocker public access. Only PoolDelegate can call this function.
    */
    function openStakeLockerToPublic() external {
        _whenProtocolNotPaused();
        _isValidPoolDelegate();
        openToPublic = true;
        emit StakeLockerOpened();
    }

    /**
        @dev Set the lockup period. Only Pool Delegate can call this function.
        @param newLockupPeriod New lockup period used to restrict unstaking.
     */
    function setLockupPeriod(uint256 newLockupPeriod) external {
        _whenProtocolNotPaused();
        _isValidPoolDelegate();
        require(newLockupPeriod <= lockupPeriod, "StakeLocker:INVALID_VALUE");
        lockupPeriod = newLockupPeriod;
    }

    /**
        @dev Transfers amt of stakeAsset to dst.
        @param dst Desintation to transfer stakeAsset to
        @param amt Amount of stakeAsset to transfer
    */
    function pull(address dst, uint256 amt) isPool external {
        stakeAsset.safeTransfer(dst, amt);
    }

    /**
        @dev Updates loss accounting for FDTs after BPTs have been burned. Only Pool can call this function.
        @param bptsBurned Amount of BPTs that have been burned
    */
    function updateLosses(uint256 bptsBurned) isPool external {
        bptLosses = bptLosses.add(bptsBurned);
        updateLossesReceived();
    }

    /************************/
    /*** Staker Functions ***/
    /************************/

    /**
        @dev Deposit amt of stakeAsset, mint FDTs to msg.sender.
        @param amt Amount of stakeAsset (BPTs) to deposit
    */
    function stake(uint256 amt) whenNotPaused external {
        _whenProtocolNotPaused();
        _isAllowed(msg.sender);

        unstakeCooldown[msg.sender] = uint256(0);  // Reset unstakeCooldown if staker had previously intended to unstake

        _updateStakeDate(msg.sender, amt);

        stakeAsset.safeTransferFrom(msg.sender, address(this), amt);
        _mint(msg.sender, amt);

        emit Stake(amt, msg.sender);
        emit Cooldown(msg.sender, uint256(0));
        emit BalanceUpdated(address(this), address(stakeAsset), stakeAsset.balanceOf(address(this)));
    }

    /**
        @dev Updates information used to calculate unstake delay.
        @param who Staker who deposited BPTs
        @param amt Amount of BPTs staker has deposited
    */
    function _updateStakeDate(address who, uint256 amt) internal {
        uint256 prevDate = stakeDate[who];
        uint256 newDate  = block.timestamp;
        if (prevDate == uint256(0)) {
            stakeDate[who] = newDate;
        } else {
            uint256 dTime  = block.timestamp.sub(prevDate);
            newDate        = prevDate.add(dTime.mul(amt).div(balanceOf(who) + amt));  // stakeDate + (now - stakeDate) * (amt / (balance + amt))
            stakeDate[who] = newDate;
        }
        emit StakeDateUpdated(who, newDate);
    }

    /**
        @dev Activates the cooldown period to unstake. It can't be called if the user is not staking.
    **/
    function intendToUnstake() external {
        require(balanceOf(msg.sender) != uint256(0), "StakeLocker:ZERO_BALANCE");
        unstakeCooldown[msg.sender] = block.timestamp;
        emit Cooldown(msg.sender, block.timestamp);
    }

    /**
        @dev Cancels an initiated unstake by resetting unstakeCooldown.
     */
    function cancelUnstake() external {
        require(unstakeCooldown[msg.sender] != uint256(0), "StakeLocker:NOT_UNSTAKING");
        unstakeCooldown[msg.sender] = 0;
        emit Cooldown(msg.sender, uint256(0));
    }

    /**
        @dev Withdraw amt of stakeAsset minus any losses, claim interest, burn FDTs for msg.sender.
        @param amt Amount of stakeAsset (BPTs) to withdraw
    */
    function unstake(uint256 amt) external canUnstake {
        _whenProtocolNotPaused();
        require(isUnstakeAllowed(msg.sender),                               "StakeLocker:OUTSIDE_COOLDOWN");
        require(stakeDate[msg.sender].add(lockupPeriod) <= block.timestamp, "StakeLocker:FUNDS_LOCKED");

        updateFundsReceived();   // Account for any funds transferred into contract since last call
        _burn(msg.sender, amt);  // Burn the corresponding FDT balance.
        withdrawFunds();         // Transfer full entitled liquidityAsset interest

        stakeAsset.safeTransfer(msg.sender, amt.sub(recognizeLosses()));  // Unstake amt minus losses

        emit Unstake(amt, msg.sender);
        emit BalanceUpdated(address(this), address(stakeAsset), stakeAsset.balanceOf(address(this)));
    }

     /**
        @dev Withdraws all available FDT interest earned for a token holder.
    */
    function withdrawFunds() public override {
        _whenProtocolNotPaused();

        uint256 withdrawableFunds = _prepareWithdraw();

        if (withdrawableFunds > uint256(0)) {
            fundsToken.safeTransfer(msg.sender, withdrawableFunds);
            emit BalanceUpdated(address(this), address(fundsToken), fundsToken.balanceOf(address(this)));

            _updateFundsTokenBalance();
        }
    }

    /**
        @dev Transfer StakerLockerFDTs.
        @param from Address sending   StakeLockerFDTs
        @param to   Address receiving StakeLockerFDTs
        @param wad  Amount of FDTs to transfer
    */
    function _transfer(address from, address to, uint256 wad) internal override canUnstake {
        _whenProtocolNotPaused();
        if (!_globals().isExemptFromTransferRestriction(from) && !_globals().isExemptFromTransferRestriction(to)) {
            require(isReceiveAllowed(unstakeCooldown[to]),    "StakeLocker:RECIPIENT_NOT_ALLOWED");  // Recipient must not be currently unstaking
            require(recognizableLossesOf(from) == uint256(0), "StakeLocker:RECOG_LOSSES");           // If a staker has unrecognized losses, they must recognize losses through unstake
            _updateStakeDate(to, wad);                                                               // Update stake date of recipient
        }
        super._transfer(from, to, wad);
    }

    /***********************/
    /*** Admin Functions ***/
    /***********************/

    /**
        @dev Triggers paused state. Halts functionality for certain functions.
    */
    function pause() external {
        _isValidAdminOrPoolDelegate();
        super._pause();
    }

    /**
        @dev Triggers unpaused state. Returns functionality for certain functions.
    */
    function unpause() external {
        _isValidAdminOrPoolDelegate();
        super._unpause();
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    /**
        @dev View function to indicate if cooldown period has passed for msg.sender and if they are in the unstake window
    */
    function isUnstakeAllowed(address from) public view returns (bool) {
        IGlobals globals = _globals();
        return block.timestamp - (unstakeCooldown[from] + globals.stakerCooldownPeriod()) <= globals.stakerUnstakeWindow();
    }

    /**
        @dev View function to indicate if recipient is allowed to receive a transfer.
        This is only possible if they have zero cooldown or they are past their unstake window.
    */
    function isReceiveAllowed(uint256 unstakeCooldown) public view returns (bool) {
        IGlobals globals = _globals();
        return block.timestamp > unstakeCooldown + globals.stakerCooldownPeriod() + globals.stakerUnstakeWindow();
    }

    /**
        @dev Function to determine if msg.sender is eligible to trigger pause/unpause.
    */
    function _isValidAdminOrPoolDelegate() internal view {
        require(msg.sender == IPool(pool).poolDelegate() || IPool(pool).admins(msg.sender), "StakeLocker:UNAUTHORIZED");
    }

    /**
        @dev Function to determine if msg.sender is eligible to trigger pause/unpause.
    */
    function _isValidPoolDelegate() internal view {
        require(msg.sender == IPool(pool).poolDelegate(), "StakeLocker:UNAUTHORIZED");
    }

    /**
        @dev Internal function to check whether `msg.sender` is allowed to stake.
    */
    function _isAllowed(address user) internal view {
        require(
            openToPublic || allowed[user] || user == IPool(pool).poolDelegate(),
            "StakeLocker:MSG_SENDER_NOT_ALLOWED"
        );
    }

    /**
        @dev Helper function to return interface of MapleGlobals.
    */
    function _globals() internal view returns(IGlobals) {
        return IGlobals(IPoolFactory(IPool(pool).superFactory()).globals());
    }

    /**
        @dev Function to block functionality of functions when protocol is in a paused state.
    */
    function _whenProtocolNotPaused() internal {
        require(!_globals().protocolPaused(), "StakeLocker:PROTOCOL_PAUSED");
    }

}
