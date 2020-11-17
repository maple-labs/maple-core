// SPDX-License-Identifier: MIT

pragma solidity 0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./Token/IFundsDistributionToken.sol";
import "./Token/FundsDistributionToken.sol";
import "./Math/CalcBPool.sol";
import "./interface/IBPool.sol";
import "./LiquidAssetLockerFactory.sol";

// @title IMapleGlobals interacts with the core MapleGlobals.sol contract.
interface IMapleGlobals {
    function mapleToken() external view returns (address);

    function stakeAmountRequired() external view returns (uint256);
}

// @title ILPStakeLockerFactory is responsbile for instantiating/initializing a staked asset locker.
interface ILPStakeLockerFactory {
    function newLocker(address _stakedAsset, address _liquidAsset) external returns (address);
}

// @title ILPStakeLocker interfaces with the staked asset locker of the liquidity pool.
interface ILPStakeLocker {
    function stake(uint256 _amountStakedAsset) external returns (uint256);

    function unstake(uint256 _amountStakedAsset) external returns (uint256);

    function withdrawUnstaked(uint256 _amountUnstaked) external returns (uint256);

    function withdrawInterest() external returns (uint256);
}

interface ILiquidAssetLockerFactory {
    function newLocker(address _liquidAsset) external returns (address);

    function isLiquidAssetLocker(address _locker) external returns (bool);
}

// @title LP is the core liquidity pool contract.
contract LiquidityPool is IFundsDistributionToken, FundsDistributionToken {
    using SafeMathInt for int256;
    using SignedSafeMath for int256;
    using SafeMath for uint256;

    // The dividend token for this contract's FundsDistributionToken.
    IERC20 private ILiquidAsset;

    //FUNDS TOKEN IS ILiquidAsset
    IERC20 private fundsToken;

    // The factory for instantiating staked asset lockers.
    ILPStakeLockerFactory private IStakeLockerFactory;

    // The staked asset for this liquidity pool (the Balancer Pool).
    IERC20 private IStakedAsset;

    // The staked asset locker which escrows the staked asset.
    ILPStakeLocker private IStakedAssetLocker;

    // The maple globals contract.
    IMapleGlobals private MapleGlobals;

    // @notice The amount of LiquidAsset tokens (dividends) currently present and accounted for in this contract.
    uint256 public fundsTokenBalance;

    // @notice The asset deposited by lenders into the LiquidAssetLocker, for funding loans.
    address public liquidAsset;

    address public immutable LiquidAssetLocker;

    // @notice The asset deposited by stakers into the stakedAssetLocker, for liquidation during defaults.
    address public stakedAsset;

    // @notice The address of the staked asset locker, escrowing the staked asset.
    address public immutable stakedAssetLocker; //supports 8 for fixed memory

    // @notice The pool delegate which has full authority over the liquidity pool and investment decisions.
    address public poolDelegate;

    // @notice true if the Liquidity Pool is fully set up and delegate meets staking criteria.
    bool public isFinalized;
    //@notice decimals() for liquid asset
    uint8 private liquidAssetDecimals;
    // This is 10^k where k = liquidAsset decimals, IE, it is one liquid asset unit in 'wei'
    uint256 private immutable _ONELiquidAsset;

    constructor(
        address _liquidAsset,
        address _stakedAsset,
        address _stakedAssetLockerFactory,
        address _LiquidAssetLockerFactory,
        string memory name,
        string memory symbol,
        address _mapleGlobals
    ) public FundsDistributionToken(name, symbol) {
        require(
            address(_liquidAsset) != address(0),
            "FDT_ERC20Extension: INVALID_FUNDS_TOKEN_ADDRESS"
        );

        liquidAsset = _liquidAsset;
        stakedAsset = _stakedAsset;
        ILiquidAsset = IERC20(_liquidAsset);
        fundsToken = ILiquidAsset;
        IStakeLockerFactory = ILPStakeLockerFactory(_stakedAssetLockerFactory);
        MapleGlobals = IMapleGlobals(_mapleGlobals);
        poolDelegate = tx.origin;
        liquidAssetDecimals = ERC20(liquidAsset).decimals();
        _ONELiquidAsset = 10**(liquidAssetDecimals);
        stakedAssetLocker = makeStakeLocker(_stakedAsset);
        LiquidAssetLocker = address(
            ILiquidAssetLockerFactory(_LiquidAssetLockerFactory).newLocker(liquidAsset)
        );
    }

    function makeStakeLocker(address _stakedAsset) private returns (address) {
        require(
            IBPool(_stakedAsset).isBound(MapleGlobals.mapleToken()) &&
                IBPool(_stakedAsset).isBound(liquidAsset) &&
                IBPool(_stakedAsset).isFinalized() &&
                (IBPool(_stakedAsset).getNumTokens() == 2),
            "FDT_LP.makeStakeLocker: BALANCER_POOL_NOT_VALID"
        );
        address _stakedAssetLocker = IStakeLockerFactory.newLocker(_stakedAsset, liquidAsset);
        return _stakedAssetLocker;
    }

    /**
     * @notice Check the size of the poolDelegate's stake held in the stakeLocker and finalize the pool
     */
    function finalize() external {
        uint256 _minStake = MapleGlobals.stakeAmountRequired();
        require(
            CalcBPool.BPTVal(stakedAsset, poolDelegate, liquidAsset, stakedAssetLocker) >
                _minStake.mul(_ONELiquidAsset),
            "FDT_LP.makeStakeLocker: NOT_ENOUGH_STAKE"
        );

        isFinalized = true;
    }

    // @notice deposit in liquidasset get equal parts FDT. muste approve this contract for it to work
    // @param _amt is ammount to deposit
    function deposit(uint256 _amt) external {
        //this means tether cna not be used.
        require(
            ILiquidAsset.allowance(msg.sender, address(this)) >= _amt,
            "ERR:LP:cant transfer liquidasset"
        );
        ILiquidAsset.transferFrom(msg.sender, LiquidAssetLocker, _amt);
        uint256 _mintAmt = liq2FDT(_amt);
        _mint(msg.sender, _mintAmt);
    }

    /*these are to convert between FDT of 18 decim and liquidasset locker of 0 to 256 decimals
    if we change the decimals on the FDT to match liquidasset this would not be necessary
    but that will cause frontend interface complications!
    if we dont support decimals > 18, that would half this code, but some jerk probably has a higher decimal coin
    */
    function liq2FDT(uint256 _amt) internal view returns (uint256 _out) {
        if (liquidAssetDecimals > 18) {
            _out = _amt.div(10**(liquidAssetDecimals - 18));
        } else {
            _out = _amt.mul(10**(18 - liquidAssetDecimals));
        }
        return _out;
    }

    function FDT2liq(uint256 _amt) internal view returns (uint256 _out) {
        if (liquidAssetDecimals > 18) {
            _out = _amt.mul(10**(liquidAssetDecimals - 18));
        } else {
            _out = _amt.div(10**(18 - liquidAssetDecimals));
        }
        return _out;
    }

    //"EVERYTHING BELOW THIS LINE I DID NOT WORK ON" - CHRIS, 2020 11 3
    /**
     * @notice Withdraws all available funds for a token holder
     */
    function withdrawFunds() public override {//must be public rather than external
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
