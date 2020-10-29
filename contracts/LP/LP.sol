pragma solidity ^0.7.0;

import "../Token/IFundsDistributionToken.sol";
import "../Token/FundsDistributionToken.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILPStakeLockerFactory {
    function newLocker(address _stakedAsset, address _liquidAsset)
        external
        returns (address);
}

interface IMapleGlobals {
    function MapleToken() external view returns (address);
}

interface IBpool {
    function isFinalized() external view returns (bool);

    function isBound(address) external view returns (bool);

    function getNumTokens() external view returns (uint256);
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

    // token in which the funds/dividends can be sent for the FundsDistributionToken
    IERC20 private IliquidToken;
    ILPStakeLockerFactory private ILockerFactory;
    IERC20 private IstakedAsset;
    ILPStakeocker private IstakedAssetLocker;
    IMapleGlobals private MapleGlobals;
    // balance of fundsToken that the FundsDistributionToken currently holds
    uint256 public fundsTokenBalance;

    // Instantiated during constructor()
    uint256 public stakerFeeBasisPoints;
    uint256 public ongoingFeeBasisPoints;
    address public liquidAsset;
    address public stakedAsset;
    address[] public stakedAssetLockers; //supports 8 for fixed memory
    address public poolDelegate;

    constructor(
        address _liquidAsset,
        address _stakedAsset,
        address _stakedAssetLockerFactory,
        string memory name,
        string memory symbol,
        address _MapleGlobalsaddy
    )
        public
        //        IERC20 _fundsToken

        FundsDistributionToken(name, symbol)
    {
        require(
            address(_liquidAsset) != address(0),
            "FDT_ERC20Extension: INVALID_FUNDS_TOKEN_ADDRESS"
        );

        // deploy _liquidAssetLocker / _stakedAssetLocker / _stakedLiquidationStrategy here ??
        // assign PoolInvestorWhitelist inherently (singular contract) ... or deploy (factory) ??

        // ierc20
        //IliquidToken = _fundsToken;

        // uint
        // StakerFeeBasisPoints = _stakerFeeBasisPoints;
        // OngoingFeeBasisPoints = _ongoingFeeBasisPoints;

        // address
        liquidAsset = _liquidAsset;
        stakedAsset = _stakedAsset;
        IliquidToken = IERC20(_liquidAsset);
        //IstakedAsset = IERC20(_stakedAsset);
        ILockerFactory = ILPStakeLockerFactory(_stakedAssetLockerFactory);
        stakedAssetLockers.push(newStakeLocker(_stakedAsset));
        //addStakeLocker(_stakedAsset);
        MapleGlobals = IMapleGlobals(_MapleGlobalsaddy);
        //IstakedAssetLocker = ILPStakeocker(stakedAssetLockers[0]);
        // bool
        // PublicPool = _publicPool;
    }

    function newStakeLocker(address _stakedAsset)
        private
        returns (address _stakedAssetLocker)
    {
        _stakedAssetLocker = ILockerFactory.newLocker(
            _stakedAsset,
            liquidAsset
        );
    }

    function addStakeLocker(address _stakedAsset) external returns (bool) {
        require(
            IBpool(_stakedAsset).isBound(MapleGlobals.MapleToken()) &&
                IBpool(_stakedAsset).isBound(liquidAsset) &&
                IBpool(_stakedAsset).isFinalized() &&
                IBpool(_stakedAsset).isFinalized() &&
                (IBpool(_stakedAsset).getNumTokens() == 2),
            "FDT_LP.addStakeLocker: BALANCER_POOL_NOT_ELIDGEABLE"
        );
        stakedAssetLockers.push(newStakeLocker(_stakedAsset));
    }

    /*
    modifier onlyIliquidToken() {
        require(
            msg.sender == address(IliquidToken),
            "FDT_ERC20Extension.onlyIliquidToken: UNAUTHORIZED_SENDER"
        );
        _;
    }
*/
    /**
     * @notice Withdraws all available funds for a token holder
     */
    function withdrawFunds() external override {
        uint256 withdrawableFunds = _prepareWithdraw();

        require(
            IliquidToken.transfer(msg.sender, withdrawableFunds),
            "FDT_ERC20Extension.withdrawFunds: TRANSFER_FAILED"
        );

        _updateIliquidTokenBalance();
    }

    /**
     * @dev Updates the current funds token balance
     * and returns the difference of new and previous funds token balances
     * @return A int256 representing the difference of the new and previous funds token balance
     */
    function _updateIliquidTokenBalance() internal returns (int256) {
        uint256 prevIliquidTokenBalance = fundsTokenBalance;

        fundsTokenBalance = IliquidToken.balanceOf(address(this));

        return int256(fundsTokenBalance).sub(int256(prevIliquidTokenBalance));
    }

    /**
     * @notice Register a payment of funds in tokens. May be called directly after a deposit is made.
     * @dev Calls _updateIliquidTokenBalance(), whereby the contract computes the delta of the previous and the new
     * funds token balance and increments the total received funds (cumulative) by delta by calling _registerFunds()
     */
    function updateFundsReceived() external {
        int256 newFunds = _updateIliquidTokenBalance();

        if (newFunds > 0) {
            _distributeFunds(newFunds.toUint256Safe());
        }
    }
}
