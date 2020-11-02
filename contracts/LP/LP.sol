pragma solidity ^0.7.0;
import "../Token/IFundsDistributionToken.sol";
import "../Token/FundsDistributionToken.sol";
import "../Math/CalcBPool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interface/IBPool.sol";
interface ILPStakeLockerFactory {
    function newLocker(address _stakedAsset, address _liquidAsset)
        external
        returns (address);
}

interface IMapleGlobals {
    function mapleToken() external view returns (address);
}

interface ILPStakeocker {
    function stake(uint256 _amountStakedAsset) external returns (uint256);

    function unstake(uint256 _amountStakedAsset) external returns (uint256);

    function withdrawUnstaked(uint256 _amountUnstaked)
        external
        returns (uint256);

    function withdrawInterest() external returns (uint256);
}

contract LP is IFundsDistributionToken, FundsDistributionToken {
    using SafeMathInt for int256;
    using SignedSafeMath for int256;
    using SafeMath for uint256;
    // token in which the funds/dividends can be sent for the FundsDistributionToken
    IERC20 private ILiquidAsset;
    ILPStakeLockerFactory private ILockerFactory;
    IERC20 private IStakedAsset;
    ILPStakeocker private IStakedAssetLocker;
    IMapleGlobals private MapleGlobals;
    uint256 public liquidTokenBalance;

    // Instantiated during constructor()
    uint256 public stakerFeeBasisPoints;
    uint256 public ongoingFeeBasisPoints;
    address public liquidAsset;
    address public stakedAsset;
    address public stakedAssetLocker; //supports 8 for fixed memory
    address public poolDelegate;
    uint256 public minStake = 100;//min stake in usd/usdc/dai SHOULD BE IN GLOBALS!!!!
    uint tokenOne;
    constructor(
        address _liquidAsset,
        address _stakedAsset,
        address _stakedAssetLockerFactory,
        string memory name,
        string memory symbol,
        address _MapleGlobalsaddy
    )
        public

        FundsDistributionToken(name, symbol)
    {
        require(
            address(_liquidAsset) != address(0),
            "FDT_ERC20Extension: INVALID_FUNDS_TOKEN_ADDRESS"
        );

        liquidAsset = _liquidAsset;
        stakedAsset = _stakedAsset;
        ILiquidAsset = IERC20(_liquidAsset);
        ILockerFactory = ILPStakeLockerFactory(_stakedAssetLockerFactory);
        MapleGlobals = IMapleGlobals(_MapleGlobalsaddy);
        poolDelegate = tx.origin;
        tokenOne = 10**ERC20(liquidAsset).decimals();
        makeStakeLocker(_stakedAsset);
    }

    function makeStakeLocker(address _stakedAsset) private {
        require(
            IBPool(_stakedAsset).isBound(MapleGlobals.mapleToken()) &&
                IBPool(_stakedAsset).isBound(liquidAsset) &&
                IBPool(_stakedAsset).isFinalized() &&
                (IBPool(_stakedAsset).getNumTokens() == 2),
            "FDT_LP.makeStakeLocker: BALANCER_POOL_NOT_VALID"
        );
        //this is to test the function but needs to be changed to be applied to the delegate's stake in the locker
        require(CalcBPool.BPTVal(_stakedAsset,poolDelegate,liquidAsset) > minStake.mul(tokenOne), "FDT_LP.makeStakeLocker: NOT_ENOUGH_STAKE");
        stakedAssetLocker = ILockerFactory.newLocker(
            _stakedAsset,
            liquidAsset
        );
    }

    /**
     * @notice Withdraws all available funds for a token holder
     */
    function withdrawFunds() external override {
        uint256 withdrawableFunds = _prepareWithdraw();

        require(
            ILiquidAsset.transfer(msg.sender, withdrawableFunds),
            "FDT_ERC20Extension.withdrawFunds: TRANSFER_FAILED"
        );

        _updateILiquidAssetBalance();
    }

    /**
     * @dev Updates the current funds token balance
     * and returns the difference of new and previous funds token balances
     * @return A int256 representing the difference of the new and previous funds token balance
     */
    function _updateILiquidAssetBalance() internal returns (int256) {
        uint256 prevILiquidAssetBalance = liquidTokenBalance;

        liquidTokenBalance = ILiquidAsset.balanceOf(address(this));

        return int256(liquidTokenBalance).sub(int256(prevILiquidAssetBalance));
    }

    /**
     * @notice Register a payment of funds in tokens. May be called directly after a deposit is made.
     * @dev Calls _updateILiquidAssetBalance(), whereby the contract computes the delta of the previous and the new
     * funds token balance and increments the total received funds (cumulative) by delta by calling _registerFunds()
     */
    function updateFundsReceived() external {
        int256 newFunds = _updateILiquidAssetBalance();

        if (newFunds > 0) {
            _distributeFunds(newFunds.toUint256Safe());
        }
    }
}
