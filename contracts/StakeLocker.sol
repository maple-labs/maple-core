// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./token/FDT.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IPoolFactory.sol";
import "./interfaces/IGlobals.sol";

/// @title StakeLocker is responsbile for escrowing staked assets and distributing a portion of interest payments.
contract StakeLocker is FDT {

    using SafeMathInt    for int256;
    using SignedSafeMath for int256;

    uint256 constant WAD = 10 ** 18;  // Scaling factor for synthetic float division.

    IERC20  public immutable stakeAsset;  // The asset deposited by stakers into this contract, for liquidation during defaults.
    
    address public immutable liquidityAsset;  // The LiquidityAsset for the Pool as well as the dividend token for this contract.
    address public immutable owner;           // The parent liquidity pool.

    mapping(address => uint256) public stakeDate;  // Map address to effective deposit date value

    event BalanceUpdated(address who, address token, uint256 balance);

    constructor(
        address _stakeAsset,
        address _liquidityAsset,
        address _owner
    ) FDT("Maple Stake Locker", "MPLSTAKE", _liquidityAsset) public {
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

    function _globals() internal view returns(IGlobals) {
        return IGlobals(IPoolFactory(IPool(owner).superFactory()).globals());
    }

    /**
        @dev Deposit amt of stakeAsset, mint FDTs to msg.sender.
        @param amt Amount of stakeAsset (BPTs) to deposit.
    */
    function stake(uint256 amt) external {
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
        require(amt <= getUnstakeableBalance(msg.sender), "Stakelocker:AMT_GT_UNSTAKEABLE_BALANCE");

        updateFundsReceived();
        withdrawFunds();
        _burn(msg.sender, amt);

        require(stakeAsset.transfer(msg.sender, amt), "StakeLocker:UNSTAKE_TRANSFER");

        emit Unstake(amt, msg.sender);
        emit BalanceUpdated(address(this), address(stakeAsset), stakeAsset.balanceOf(address(this)));
    }

    /** 
        @dev Withdraw ETH directly from this locker.
        @param dst Address to send ETH to.
    */
    function withdrawETH(address payable dst) external isGovernor {
        dst.transfer(address(this).balance);
    }

    /** 
        @dev Updates information used to calculate unstake delay.
        @param who The staker who deposited BPTs.
        @param amt Amount of BPTs staker has deposited.
    */
    function _updateStakeDate(address who, uint256 amt) internal {
        if (stakeDate[who] == 0) {
            stakeDate[who] = block.timestamp;
        } else {
            uint256 stkDate = stakeDate[who];
            uint256 coef    = (WAD.mul(amt)).div(balanceOf(who) + amt); 
            stakeDate[who]  = (stkDate.mul(WAD).add((block.timestamp.sub(stkDate)).mul(coef))).div(WAD);  // date + (now - stkDate) * coef
        }
    }

    /**
        @dev Returns information for staker's unstakeable balance.
        @param staker The address to view information for.
        @return Amount of BPTs staker can unstake.
    */
    // TODO: Handle case where unstakeDelay == 0 (use similar/same logic as calcWithdrawPenalty)
    function getUnstakeableBalance(address staker) public view returns (uint256) {
        uint256 bal  = balanceOf(staker);
        uint256 time = (block.timestamp - stakeDate[staker]) * WAD;
        uint256 out  = ((time / (_globals().unstakeDelay())) * bal) / WAD;
        // The plus one is to avoid division by 0 if unstakeDelay is 0, creating 1 second inaccuracy
        // Also i do indeed want this to return 0 if denominator is less than WAD
        if (out > bal) {
            out = bal;
        }
        return out;
    }

    // TODO: Make this handle transfer of time lock more properly, parameterize _updateStakeDate
    //      to these ends to save code.
    //      can improve this so the updated age of tokens reflects their age in the senders wallets
    //      right now it simply is equivalent to the age update if the receiver was making a new stake.
    function _transfer(address from, address to, uint256 amt) internal override canUnstake {
        super._transfer(from, to, amt);
        _updateStakeDate(to, amt);
    }
}
