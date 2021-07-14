// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { SignedSafeMath }    from "../../../../lib/openzeppelin-contracts/contracts/math/SignedSafeMath.sol";
import { IERC20, SafeERC20 } from "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/SafeERC20.sol";
import { Pausable }          from "../../../../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";

import { SafeMathInt } from "../../../libraries/math/v1/SafeMathInt.sol";

import { IBasicFDT }     from "../../funds-distribution-token/v1/interfaces/IBasicFDT.sol";
import { IMapleGlobals } from "../../globals/v1/interfaces/IMapleGlobals.sol";
import { IPool }         from "../../pool/v1/interfaces/IPool.sol";
import { IPoolFactory }  from "../../pool/v1/interfaces/IPoolFactory.sol";

import { IStakeLocker } from "./interfaces/IStakeLocker.sol";

import { StakeLockerFDT } from "./StakeLockerFDT.sol";

/// @title StakeLocker holds custody of stakeAsset tokens for a given Pool and earns revenue from interest.
contract StakeLocker is IStakeLocker, StakeLockerFDT, Pausable {

    using SafeMathInt    for int256;
    using SignedSafeMath for int256;
    using SafeERC20      for IERC20;

    uint256 constant WAD = 10 ** 18;  // Scaling factor for synthetic float division.

    IERC20  public override immutable stakeAsset;

    address public override immutable liquidityAsset;
    address public override immutable pool;

    uint256 public override lockupPeriod;

    mapping(address => uint256)                     public override stakeDate;
    mapping(address => uint256)                     public override unstakeCooldown;
    mapping(address => bool)                        public override allowed;
    mapping(address => mapping(address => uint256)) public override custodyAllowance;
    mapping(address => uint256)                     public override totalCustodyAllowance;

    bool public override openToPublic;  // Boolean opening StakeLocker to public for staking BPTs

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

    function setAllowlist(address staker, bool status) public override {
        _whenProtocolNotPaused();
        _isValidPoolDelegate();
        allowed[staker] = status;
        emit AllowListUpdated(staker, status);
    }

    function openStakeLockerToPublic() external override {
        _whenProtocolNotPaused();
        _isValidPoolDelegate();
        openToPublic = true;
        emit StakeLockerOpened();
    }

    function setLockupPeriod(uint256 newLockupPeriod) external override {
        _whenProtocolNotPaused();
        _isValidPoolDelegate();
        require(newLockupPeriod <= lockupPeriod, "SL:INVALID_VALUE");
        lockupPeriod = newLockupPeriod;
        emit LockupPeriodUpdated(newLockupPeriod);
    }

    function pull(address dst, uint256 amt) isPool external override {
        stakeAsset.safeTransfer(dst, amt);
    }

    function updateLosses(uint256 bptsBurned) isPool external override {
        bptLosses = bptLosses.add(bptsBurned);
        updateLossesReceived();
    }

    /************************/
    /*** Staker Functions ***/
    /************************/

    function stake(uint256 amt) whenNotPaused external override {
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

    function intendToUnstake() external override {
        require(balanceOf(msg.sender) != uint256(0), "SL:ZERO_BALANCE");
        unstakeCooldown[msg.sender] = block.timestamp;
        emit Cooldown(msg.sender, block.timestamp);
    }

    function cancelUnstake() external override {
        require(unstakeCooldown[msg.sender] != uint256(0), "SL:NOT_UNSTAKING");
        unstakeCooldown[msg.sender] = 0;
        emit Cooldown(msg.sender, uint256(0));
    }

    function unstake(uint256 amt) external override canUnstake(msg.sender) {
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

    function withdrawFunds() public override(IBasicFDT, IStakeLocker) {
        _whenProtocolNotPaused();

        uint256 withdrawableFunds = _prepareWithdraw();

        if (withdrawableFunds == uint256(0)) return;

        fundsToken.safeTransfer(msg.sender, withdrawableFunds);
        emit BalanceUpdated(address(this), address(fundsToken), fundsToken.balanceOf(address(this)));

        _updateFundsTokenBalance();
    }

    function increaseCustodyAllowance(address custodian, uint256 amount) external override {
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

    function transferByCustodian(address from, address to, uint256 amount) external override {
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

    function pause() external override {
        _isValidPoolDelegateOrPoolAdmin();
        super._pause();
    }

    function unpause() external override {
        _isValidPoolDelegateOrPoolAdmin();
        super._unpause();
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    function isUnstakeAllowed(address from) public override view returns (bool) {
        IMapleGlobals globals = _globals();
        return (block.timestamp - (unstakeCooldown[from] + globals.stakerCooldownPeriod())) <= globals.stakerUnstakeWindow();
    }

    function isReceiveAllowed(uint256 _unstakeCooldown) public override view returns (bool) {
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
