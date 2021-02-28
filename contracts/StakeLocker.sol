// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

import "./interfaces/IGlobals.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IPoolFactory.sol";

import "./token/StakeLockerFDT.sol";

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";

/// @title StakeLocker is responsbile for escrowing staked assets and distributing a portion of interest payments.
contract StakeLocker is StakeLockerFDT, Pausable {

    using SafeMathInt    for int256;
    using SignedSafeMath for int256;

    uint256 constant WAD = 10 ** 18;  // Scaling factor for synthetic float division.

    IERC20  public immutable stakeAsset;  // The asset deposited by stakers into this contract, for liquidation during defaults.
    
    address public immutable liquidityAsset;  // The LiquidityAsset for the Pool as well as the dividend token for this contract.
    address public immutable owner;           // The parent liquidity pool.

    mapping(address => uint256) public stakeDate; // Map address to effective deposit date value
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

    /** 
        canUnstake enables unstaking in the following conditions:
            1. User is not Pool Delegate and the Pool is in Finalized state.
            2. User is Pool Delegate and the Pool is in Initialized or Deactivated state.
    */
    modifier canUnstake() {
        require(
            (msg.sender != IPool(owner).poolDelegate() && IPool(owner).poolState() == 1) || 
            IPool(owner).poolState() == 0 || IPool(owner).poolState() == 2, 
            "StakeLocker:ERR_STAKE_LOCKED"
        );
        _;
    }
    
    modifier isGovernor() {
        require(msg.sender == _globals().governor(), "StakeLocker:MSG_SENDER_NOT_GOVERNOR");
        _;
    }

    modifier isPool() {
        require(msg.sender == owner, "StakeLocker:MSG_SENDER_NOT_POOL");
        _;
    }

    function _isAllowed(address user) internal view {
        require(
            allowed[user] || user == IPool(owner).poolDelegate(), 
            "StakeLocker:MSG_SENDER_NOT_ALLOWED"
        );
    }

    function _globals() internal view returns(IGlobals) {
        return IGlobals(IPoolFactory(IPool(owner).superFactory()).globals());
    }

    function _whenProtocolNotPaused() internal {
        require(!_globals().protocolPaused(), "StakeLocker:PROTOCOL_PAUSED");
    }

    /**
        @dev Update user status on the allowlist. Only Pool owner can call this.
        @param user   The address to set status for.
        @param status The status of user on allowlist.
    */
    function setAllowlist(address user, bool status) isPool public {
        allowed[user] = status;
    }

    /**
        @dev Transfers amt of stakeAsset to dst.
        @param  dst Desintation to transfer stakeAsset to.
        @param  amt Amount of stakeAsset to transfer.
    */
    function pull(address dst, uint256 amt) isPool public returns(bool) {
        return stakeAsset.transfer(dst, amt);
    }

    /**
        @dev Deposit amt of stakeAsset, mint FDTs to msg.sender.
        @param amt Amount of stakeAsset (BPTs) to deposit.
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
        @dev Withdraw amt of stakeAsset, burn FDTs for msg.sender.
        @param amt Amount of stakeAsset (BPTs) to withdraw.
    */
    function unstake(uint256 amt) external canUnstake {
        _whenProtocolNotPaused();
        require(amt <= getUnstakeableBalance(msg.sender), "Stakelocker:AMT_GT_UNSTAKEABLE_BALANCE");

        amt = totalSupply() == amt && amt > 0 ? amt - 1 : amt;  // If last withdraw, subtract 1 wei to maintain FDT accounting

        updateFundsReceived();  // Account for any funds transferred into contract since last call

        uint256 recognizedLosses = recognizableLossesOf(msg.sender);  // Get all losses of user

        _burn(msg.sender, amt);  // Burn the corresponding FDT balance.
        recognizeLosses();       // Update loss accounting for Staker, decrement `bptLosses`
        withdrawFunds();         // Transfer full entitled interest

        require(stakeAsset.transfer(msg.sender, amt.sub(recognizedLosses)), "StakeLocker:UNSTAKE_TRANSFER");  // Unstake amt minus losses

        emit Unstake(amt, msg.sender);
        emit BalanceUpdated(address(this), address(stakeAsset), stakeAsset.balanceOf(address(this)));
    }

    /** 
        @dev Updates information used to calculate unstake delay.
        @param who The staker who deposited BPTs.
        @param amt Amount of BPTs staker has deposited.
    */
    function _updateStakeDate(address who, uint256 amt) internal {
        uint256 stkDate = stakeDate[who];
        if (stkDate == 0) {
            stakeDate[who] = block.timestamp;
        } else {
            uint256 coef   = WAD.mul(amt).div(balanceOf(who) + amt); 
            stakeDate[who] = stkDate.add(((block.timestamp.sub(stkDate)).mul(coef)).div(WAD));  // date + (now - stkDate) * coef
        }
    }

    /**
        @dev Returns information for staker's unstakeable balance.
        @param staker The address to view information for.
        @return balance Amount of BPTs staker can unstake.
    */
    function getUnstakeableBalance(address staker) public view returns (uint256 balance) {
        uint256 bal          = balanceOf(staker);
        uint256 passedTime   = block.timestamp - stakeDate[staker];
        uint256 unstakeDelay = _globals().unstakeDelay();
        uint256 out          = unstakeDelay != uint256(0) ? passedTime.mul(bal).div(unstakeDelay) : bal;
        balance = out > bal ? bal : out;
    }

    /**
     * @dev Withdraws all available funds for a token holder
     */
    function withdrawFunds() public override {
        _whenProtocolNotPaused();
        
        uint256 withdrawableFunds = _prepareWithdraw();

        require(fundsToken.transfer(msg.sender, withdrawableFunds), "FDT:TRANSFER_FAILED");

        _updateFundsTokenBalance();
    }

    function updateLosses(uint256 bptsBurned) isPool external {
        bptLosses = bptLosses.add(bptsBurned);
        updateLossesReceived();
    }

    // TODO: Make this handle transfer of time lock more properly, parameterize _updateStakeDate
    //      to these ends to save code.
    //      can improve this so the updated age of tokens reflects their age in the senders wallets
    //      right now it simply is equivalent to the age update if the receiver was making a new stake.
    function _transfer(address from, address to, uint256 amt) internal override canUnstake {
        _whenProtocolNotPaused();
        _isAllowed(to);
        super._transfer(from, to, amt);
        _updateStakeDate(to, amt);
    }

    /**
        @dev Triggers stopped state.
             The contract must not be paused.
    */
    function pause() external {
        _isValidAdminOrPoolDelegate();
        super._pause();
    }

    /**
        @dev Returns to normal state.
             The contract must be paused.
    */
    function unpause() external {
        _isValidAdminOrPoolDelegate();
        super._unpause();
    }

    function _isValidAdminOrPoolDelegate() internal view {
        require(msg.sender == IPool(owner).poolDelegate() || IPool(owner).admins(msg.sender), "StakeLocker:UNAUTHORIZED");
    }
    
}
