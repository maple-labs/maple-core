// SPDX-License-Identifier: MIT
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
    address public immutable owner;           // The parent liquidity pool.

    mapping(address => uint256) public stakeDate; // Map address to effective stake date value
    mapping(address => bool)    public allowed;   // Map address to allowed status

    event BalanceUpdated(address who, address token, uint256 balance);

    constructor(
        address _stakeAsset,
        address _liquidityAsset,
        address _owner
    ) StakeLockerFDT("Maple Stake Locker", "MPLSTAKE", _liquidityAsset) public {
        liquidityAsset = _liquidityAsset;
        stakeAsset     = IERC20(_stakeAsset);
        owner          = _owner;
    }

    event   Stake(uint256 _amount, address _staker);
    event Unstake(uint256 _amount, address _staker);
    event AllowListUpdated(address _user, bool _status);

    /** 
        @dev canUnstake enables unstaking in the following conditions:
        1. User is not Pool Delegate and the Pool is in Finalized state.
        2. The Pool is in Initialized or Deactivated state.
    */
    modifier canUnstake() {
        require(
            (msg.sender != IPool(owner).poolDelegate() && IPool(owner).isPoolFinalized()) || 
            !IPool(owner).isPoolFinalized(), 
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
        require(msg.sender == owner, "StakeLocker:MSG_SENDER_NOT_POOL");
        _;
    }

    /** 
        @dev Internal function to check whether `msg.sender` is allowed to stake.
    */
    function _isAllowed(address user) internal view {
        require(
            allowed[user] || user == IPool(owner).poolDelegate(), 
            "StakeLocker:MSG_SENDER_NOT_ALLOWED"
        );
    }

    /** 
        @dev Helper function to return interface of MapleGlobals.
    */
    function _globals() internal view returns(IGlobals) {
        return IGlobals(IPoolFactory(IPool(owner).superFactory()).globals());
    }

    /**
        @dev Function to block functionality of functions when protocol is in a paused state.
    */
    function _whenProtocolNotPaused() internal {
        require(!_globals().protocolPaused(), "StakeLocker:PROTOCOL_PAUSED");
    }

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
        @dev Transfers amt of stakeAsset to dst.
        @param dst Desintation to transfer stakeAsset to
        @param amt Amount of stakeAsset to transfer
    */
    function pull(address dst, uint256 amt) isPool public returns(bool) {
        return stakeAsset.transfer(dst, amt);
    }

    /**
        @dev Deposit amt of stakeAsset, mint FDTs to msg.sender.
        @param amt Amount of stakeAsset (BPTs) to deposit
    */
    function stake(uint256 amt) whenNotPaused external {
        _whenProtocolNotPaused();
        _isAllowed(msg.sender);
        require(stakeAsset.transferFrom(msg.sender, address(this), amt), "StakeLocker:STAKE_TRANSFER_FROM");

        _updateStakeDate(msg.sender, amt);
        _mint(msg.sender, amt);

        emit Stake(amt, msg.sender);
        emit BalanceUpdated(address(this), address(stakeAsset), stakeAsset.balanceOf(address(this)));
    }

    /**
        @dev Withdraw amt of stakeAsset minus any losses, claim interest, burn FDTs for msg.sender.
        @param amt Amount of stakeAsset (BPTs) to withdraw
    */
    function unstake(uint256 amt) external canUnstake {
        _whenProtocolNotPaused();
        require(amt <= getUnstakeableBalance(msg.sender), "Stakelocker:AMT_GT_UNSTAKEABLE_BALANCE");

        amt = totalSupply() == amt && amt > 0 ? amt - 1 : amt;  // If last withdraw, subtract 1 wei to maintain FDT accounting

        updateFundsReceived();   // Account for any funds transferred into contract since last call
        _burn(msg.sender, amt);  // Burn the corresponding FDT balance.
        withdrawFunds();         // Transfer full entitled interest

        require(stakeAsset.transfer(msg.sender, amt.sub(recognizeLosses())), "StakeLocker:UNSTAKE_TRANSFER");  // Unstake amt minus losses

        emit Unstake(amt, msg.sender);
        emit BalanceUpdated(address(this), address(stakeAsset), stakeAsset.balanceOf(address(this)));
    }

    /** 
        @dev Updates information used to calculate unstake delay.
        @param who Staker who deposited BPTs
        @param amt Amount of BPTs staker has deposited
    */
    function _updateStakeDate(address who, uint256 amt) internal {
        uint256 stkDate = stakeDate[who];
        if (stkDate == uint256(0)) {
            stakeDate[who] = block.timestamp;
        } else {
            uint256 dTime  = block.timestamp.sub(stkDate); 
            stakeDate[who] = stkDate.add(dTime.mul(amt).div(balanceOf(who) + amt));  // depDate + (now - depDate) * (amt / (balance + amt))
        }
    }

    /**
        @dev Returns information for staker's unstakeable balance.
        @param staker The address to view information for
        @return balance Amount of BPTs staker can unstake
    */
    function getUnstakeableBalance(address staker) public view returns (uint256 balance) {
        uint256 bal          = balanceOf(staker);
        uint256 passedTime   = block.timestamp - stakeDate[staker];
        uint256 unstakeDelay = _globals().unstakeDelay();
        uint256 out          = unstakeDelay != uint256(0) ? passedTime.mul(bal).div(unstakeDelay) : bal;
        balance = out > bal ? bal : out;
    }

    /**
        @dev Withdraws all available FDT interest earned for a token holder.
    */
    function withdrawFunds() public override {
        _whenProtocolNotPaused();
        
        uint256 withdrawableFunds = _prepareWithdraw();

        fundsToken.safeTransfer(msg.sender, withdrawableFunds);

        _updateFundsTokenBalance();
    }

    /**
        @dev Updates loss accounting for FDTs after BPTs have been burned. Only Pool can call this function.
        @param bptsBurned Amount of BPTs that have been burned
    */
    function updateLosses(uint256 bptsBurned) isPool external {
        bptLosses = bptLosses.add(bptsBurned);
        updateLossesReceived();
    }

    /**
        @dev Transfer StakerLockerFDTs.
        @param from Address sending   StakeLockerFDTs
        @param to   Address receiving StakeLockerFDTs
        @param amt  Amount of FDTs to transfer
    */
    function _transfer(address from, address to, uint256 amt) internal override canUnstake {
        _whenProtocolNotPaused();
        _isAllowed(to);
        _updateStakeDate(to, amt);
        super._transfer(from, to, amt);
    }

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

    /**
        @dev Function to determine if msg.sender is eligible to trigger pause/unpause.
    */
    function _isValidAdminOrPoolDelegate() internal view {
        require(msg.sender == IPool(owner).poolDelegate() || IPool(owner).admins(msg.sender), "StakeLocker:UNAUTHORIZED");
    }
}
