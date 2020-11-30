// SPDX-License-Identifier: MIT

pragma solidity 0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./Token/IFundsDistributionToken.sol";
import "./Token/FundsDistributionToken.sol";
import "./Math/CalcBPool.sol";
import "./interface/IBPool.sol";
import "./LiquidityLockerFactory.sol";
import "./interface/IGlobals.sol";
import "./interface/ILoanVaultFactory.sol";
import "./interface/IStakeLocker.sol";
import "./interface/IStakeLockerFactory.sol";
import "./interface/ILiquidityLocker.sol";
import "./interface/ILiquidityLockerFactory.sol";

//TODO IMPLEMENT WITHDRAWL FUNCTIONS
//TODO IMPLEMENT DELETE FUNCTIONS CALLING stakedAssetLocker deleteLP()

/// @title LiquidityPool is the core contract for liquidity pools.
contract LiquidityPool is IFundsDistributionToken, FundsDistributionToken {

    using SafeMathInt for int256;
    using SignedSafeMath for int256;
    using SafeMath for uint256;
    
    // An interface for this contract's FundsDistributionToken, stored in two separate variables.
    IERC20 private ILiquidityAsset;
    IERC20 private fundsToken;

    // An interface for the asset used to stake the StakeLocker for this LiquidityPool.
    IERC20 private IStakedAsset;

    // An interface for the factory used to instantiate a StakeLocker for this LiquidityPool.
    IStakeLockerFactory private StakeLockerFactory;

    // An interface for the locker which escrows StakedAsset.
    IStakeLocker private StakeLocker;

    // An interface for the MapleGlobals contract.
    IGlobals private MapleGlobals;

    /// @notice The amount of LiquidityAsset tokens (dividends) currently present and accounted for in this contract.
    uint256 public fundsTokenBalance;

    /// @notice The asset deposited by lenders into the LiquidityLocker, for funding loans.
    address public liquidityAsset;

    // decimals() precision for the liquidityAsset.
    uint8 private liquidityAssetDecimals;

    // 10^k where k = liquidityAssetDecimals, representing one LiquidityAsset unit in 'wei'.
    uint256 private immutable _ONELiquidityAsset;

    /// @notice The LiquidityLocker owned by this contract.
    address public immutable liquidityLockerAddress;

    /// @notice The asset deposited by stakers into the StakeLocker, for liquidation during default events.
    address public stakeAsset;

    /// @notice Address of the StakeLocker, escrowing the staked asset.
    address public immutable stakeLockerAddress;

    /// @notice The pool delegate, who maintains full authority over this LiquidityPool.
    address public poolDelegate;

    /// @notice True if this LiquidityPool is setup and the poolDelegate has met staking requirements.
    bool public isFinalized;

    /// @notice True when the pool is closed, enabling poolDelegate to withdraw their stake.
    bool public isDefunct;

    constructor(
        address _liquidityAsset,
        address _stakeAsset,
        address _stakeLockerFactory,
        address _liquidityLockerFactory,
        string memory name,
        string memory symbol,
        address _mapleGlobals
    ) public FundsDistributionToken(name, symbol) {

        require(
            address(_liquidityAsset) != address(0),
            "FDT_ERC20Extension: INVALID_FUNDS_TOKEN_ADDRESS"
        );

        // Assign variables relating to the LiquidityAsset.
        liquidityAsset = _liquidityAsset;
        liquidityAssetDecimals = ERC20(liquidityAsset).decimals();
        _ONELiquidityAsset = 10**(liquidityAssetDecimals);
        ILiquidityAsset = IERC20(_liquidityAsset);
        fundsToken = ILiquidityAsset;

        // Assign misc. state variables
        stakeAsset = _stakeAsset;
        StakeLockerFactory = IStakeLockerFactory(_stakeLockerFactory);
        MapleGlobals = IGlobals(_mapleGlobals);
        poolDelegate = tx.origin;

        // Initialize the LiquidityLocker and StakeLocker.
        stakeLockerAddress = makeStakeLocker(_stakeAsset);
        liquidityLockerAddress = address(
            ILiquidityLockerFactory(_liquidityLockerFactory).newLocker(liquidityAsset)
        );

    }

    modifier finalized() {
        require(isFinalized, "LiquidityPool: IS NOT FINALIZED");
        _;
    }
    modifier notDefunct() {
        require(!isDefunct, "LiquidityPool: IS DEFUNCT");
        _;
    }
    modifier isDelegate() {
        require(msg.sender == poolDelegate, "LiquidityPool: ERR UNAUTH");
        _;
    }

    // @notice creates stake locker
    function makeStakeLocker(address _stakedAsset) private returns (address) {
        require(
            IBPool(_stakedAsset).isBound(MapleGlobals.mapleToken()) &&
                IBPool(_stakedAsset).isBound(liquidityAsset) &&
                IBPool(_stakedAsset).isFinalized() &&
                (IBPool(_stakedAsset).getNumTokens() == 2),
            "FDT_LP.makeStakeLocker: BALANCER_POOL_NOT_VALID"
        );
        address _stakedAssetLocker =
            StakeLockerFactory.newLocker(_stakedAsset, liquidityAsset, address(MapleGlobals));
        StakeLocker = IStakeLocker(_stakedAssetLocker);
        return _stakedAssetLocker;
    }

    /**
     * @notice Confirm poolDelegate's stake amount held in StakeLocker and finalize this LiquidityPool.
     */
    function finalize() external {
        uint256 _minStake = MapleGlobals.stakeAmountRequired();
        require(
            CalcBPool.BPTVal(stakeAsset, poolDelegate, liquidityAsset, stakeLockerAddress) >
                _minStake.mul(_ONELiquidityAsset),
            "FDT_LP.makeStakeLocker: NOT_ENOUGH_STAKE"
        );
        isFinalized = true;
        StakeLocker.finalizeLP();
    }

    // Note: Tether is unusable as a LiquidityAsset!
    /// @notice Liquidity providers can deposit LiqudityAsset into the LiquidityLocker, minting FDTs.
    /// @param _amt The amount of LiquidityAsset to deposit, in wei.
    function deposit(uint256 _amt) external notDefunct finalized {
        require(
            ILiquidityAsset.allowance(msg.sender, address(this)) >= _amt,
            "LiquidityPool::deposit:ERR_ALLOWANCE_LESS_THEN__AMT"
        );
        ILiquidityAsset.transferFrom(msg.sender, liquidityLockerAddress, _amt);
        uint256 _mintAmt = liq2FDT(_amt);
        _mint(msg.sender, _mintAmt);
    }

    function fundLoan(address _loanVault, uint256 _amt) external notDefunct finalized isDelegate {
        require(
            ILoanVaultFactory(MapleGlobals.loanVaultFactory()).isLoanVault(_loanVault),
            "LiquidityPool::fundLoan:ERR_LOAN_VAULT_INVALID"
        );
        ILiquidityLocker(liquidityLockerAddress).fundLoan(_loanVault, _amt);
    }

    /*these are to convert between FDT of 18 decim and liquidasset locker of 0 to 256 decimals
    if we change the decimals on the FDT to match liquidasset this would not be necessary
    but that will cause frontend interface complications!
    if we dont support decimals > 18, that would half this code, but some jerk probably has a higher decimal coin
    */
    function liq2FDT(uint256 _amt) internal view returns (uint256 _out) {
        if (liquidityAssetDecimals > 18) {
            _out = _amt.div(10**(liquidityAssetDecimals - 18));
        } else {
            _out = _amt.mul(10**(18 - liquidityAssetDecimals));
        }
        return _out;
    }

    // TODO: Optimize FDT2liq and liq2FDT 
    // TODO: Consider removing the one below if not being used after withdraw() is implemented.
    function FDT2liq(uint256 _amt) internal view returns (uint256 _out) {
        if (liquidityAssetDecimals > 18) {
            _out = _amt.mul(10**(liquidityAssetDecimals - 18));
        } else {
            _out = _amt.div(10**(18 - liquidityAssetDecimals));
        }
        return _out;
    }

    /**
     * @notice Withdraws all available funds for a token holder
     */
    function withdrawFunds() public override {
        //must be public rather than external
        uint256 withdrawableFunds = _prepareWithdraw();

        require(
            fundsToken.transfer(msg.sender, withdrawableFunds),
            "FDT_ERC20Extension.withdrawFunds: TRANSFER_FAILED"
        );

        _updateFundsTokenBalance();
    }

    /**
     * @dev Updates the current funds token balance
     * and returns the difference of new and previous funds token balances
     * @return A int256 representing the difference of the new and previous funds token balance
     */
    function _updateFundsTokenBalance() internal returns (int256) {
        uint256 _prevFundsTokenBalance = fundsTokenBalance;

        fundsTokenBalance = fundsToken.balanceOf(address(this));

        return int256(fundsTokenBalance).sub(int256(_prevFundsTokenBalance));
    }

    /**
     * @notice Register a payment of funds in tokens. May be called directly after a deposit is made.
     * @dev Calls _updateFundsTokenBalance(), whereby the contract computes the delta of the previous and the new
     * funds token balance and increments the total received funds (cumulative) by delta by calling _registerFunds()
     */
    function updateFundsReceived() external {
        int256 newFunds = _updateFundsTokenBalance();

        if (newFunds > 0) {
            _distributeFunds(newFunds.toUint256Safe());
        }
    }
}
