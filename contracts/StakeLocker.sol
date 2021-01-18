// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./token/FDT.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IGlobals.sol";

/// @title StakeLocker is responsbile for escrowing staked assets and distributing a portion of interest payments.
contract StakeLocker is FDT {

    using SafeMathInt    for int256;
    using SignedSafeMath for int256;

    uint256 constant WAD = 10 ** 18;  // Scaling factor for synthetic float division

    address public immutable stakeAsset;      // The asset deposited by stakers into this contract, for liquidation during defaults.
    address public immutable liquidityAsset;  // The LiquidityAsset for the Pool as well as the dividend token for this contract.
    address public immutable owner;           // The parent liquidity pool.
    address public immutable globals;         // Maple globals

    mapping(address => uint256) private stakeDate;  // Map address to date value (TODO: Consider making public)

    event BalanceUpdated(address who, address token, uint256 balance);

    constructor(
        address _stakeAsset,
        address _liquidityAsset,
        address _owner,
        address _globals
    ) FDT("Maple Stake Locker", "MPLSTAKE", _liquidityAsset) public {
        liquidityAsset = _liquidityAsset;
        stakeAsset     = _stakeAsset;
        owner          = _owner;
        globals        = _globals;
    }

    event   Stake(uint256 _amount, address _staker);
    event Unstake(uint256 _amount, address _staker);

    /** 
        canUnstake enables unstaking in the following conditions:
            1. User is not Pool Delegate and the Pool is active.
            2. Pool is not finalized.
            3. Pool is not active.
    */
    modifier canUnstake() {
        require(
            (msg.sender != IPool(owner).poolDelegate() && IPool(owner).isActive()) || 
            !IPool(owner).isFinalized() || 
            !IPool(owner).isActive(),
            "StakeLocker:ERR_DELEGATE_STAKE_LOCKED"
        );
        _;
    }

    modifier isLP() {
        require(msg.sender == owner, "StakeLocker:ERR_UNAUTHORIZED");
        _;
    }
    
    modifier isGovernor() {
        require(msg.sender == IGlobals(globals).governor(), "msg.sender is not Governor");
        _;
    }

    /**
        @dev Deposit amt of stakeAsset, mint FDTs to msg.sender.
        @param amt Amount of stakeAsset (BPTs) to deposit.
    */
    // TODO: Consider localizing this function to Pool.
    function stake(uint256 amt) external {
        require(
            IERC20(stakeAsset).transferFrom(msg.sender, address(this), amt),
            "StakeLocker:ERR_INSUFFICIENT_APPROVED_FUNDS"
        );
        _updateStakeDate(msg.sender, amt);
        _mint(msg.sender, amt);
        emit Stake(amt, msg.sender);
        emit BalanceUpdated(address(this), stakeAsset, IERC20(stakeAsset).balanceOf(address(this)));
    }

    /**
        @dev Withdraw amt of stakeAsset, burn FDTs for msg.sender.
        @param amt Amount of stakeAsset (BPTs) to withdraw.
    */
    // TODO: Consider localizing this function to Pool.
    function unstake(uint256 amt) external canUnstake {
        require(
            amt <= getUnstakeableBalance(msg.sender),
            "Stakelocker:ERR_AMT_REQUESTED_UNAVAILABLE"
        );
        updateFundsReceived();
        withdrawFunds(); //has to be before the transfer or they will end up here
        _transfer(msg.sender, address(this), amt);
        require(
            IERC20(stakeAsset).transferFrom(address(this), msg.sender, amt),
            "StakeLocker:ERR_STAKE_ASSET_BALANCE_DEPLETED"
        );
        _burn(address(this), amt);
        emit Unstake(amt, msg.sender);
        emit BalanceUpdated(address(this), stakeAsset, IERC20(stakeAsset).balanceOf(address(this)));
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
        @param staker The staker who deposited BPTs.
        @param amt    Amount of BPTs staker has deposited.
    */
    function _updateStakeDate(address staker, uint256 amt) internal {
        if (stakeDate[staker] == 0) {
            stakeDate[staker] = block.timestamp;
        } else {
            uint256 date = stakeDate[staker];
            // Make sure this is executed before mint or line below needs change on denominator
            uint256 coef = (WAD * amt) / (balanceOf(staker) + amt); // Yes, i want 0 if amt is too small
            // This addition will start to overflow in about 3^52 years
            stakeDate[staker] = (date * WAD + (block.timestamp - date) * coef) / WAD;
            // I know this is insane but its good trust me
        }
    }

    /**
        @dev Returns information for staker's unstakeable balance.
        @param staker The address to view information for.
        @return Amount of BPTs staker can unstake.
    */
    function getUnstakeableBalance(address staker) public view returns (uint256) {
        uint256 bal = balanceOf(staker);
        uint256 time = (block.timestamp - stakeDate[staker]) * WAD;
        uint256 out = ((time / (IGlobals(globals).unstakeDelay() + 1)) * bal) / WAD;
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
