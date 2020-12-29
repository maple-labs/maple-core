// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "./token/IFundsDistributionToken.sol";
import "./token/FundsDistributionToken.sol";
import "./math/CalcBPool.sol";
import "./interfaces/IBPool.sol";
import "./LiquidityLockerFactory.sol";
import "./interfaces/IGlobals.sol";
import "./interfaces/ILoanVaultFactory.sol";
import "./interfaces/IStakeLocker.sol";
import "./interfaces/IStakeLockerFactory.sol";
import "./interfaces/ILiquidityLocker.sol";
import "./interfaces/ILiquidityLockerFactory.sol";
import "./interfaces/ILoanTokenLockerFactory.sol";
import "./interfaces/ILoanTokenLocker.sol";
import "./interfaces/ILoanVault.sol";

// TODO: Implement the withdraw() function, so investors can withdraw LiquidityAsset from LP.
// TODO: Implement a delete function, calling stakeLocker's deleteLP() function.

/// @title LiquidityPool is the core contract for liquidity pools.
contract LiquidityPool is IERC20, ERC20 {

    using SafeMath for uint256;

    // An interface for this contract's liquidity asset, stored in two separate variables.
    IERC20 private ILiquidityAsset;

    // An interface for the asset used to stake the StakeLocker for this LiquidityPool.
    IERC20 private IStakeAsset;

    // An interface for the factory used to instantiate a StakeLocker for this LiquidityPool.
    IStakeLockerFactory private StakeLockerFactory;

    // Struct for tracking investments.
    struct FundedLoan {
        address loanVaultFunded;
        address loanTokenLocker;
        uint256 amountFunded;
        uint256 principalPaid;
        uint256 interestPaid;
        uint256 feePaid;
        uint256 excessReturned;
        // TODO: uint256 liquidationClaimed;
    }

    /// @notice Fires when this liquidity pool funds a loan.
    event LoanFunded(
        address loanVaultFunded,
        address loanTokenLocker,
        uint256 amountFunded
    );

    /// @notice Investments this liquidity pool has made into loans.
    FundedLoan[] public fundedLoans;

    /// @notice Data structure to reference loan token lockers.
    /// @dev loanTokenLockers[LOAN_VAULT][LOCKER_FACTORY] = LOCKER
    mapping(address => mapping(address => address)) public loanTokenLockers;

    // An interface for the locker which escrows StakeAsset.
    IStakeLocker private StakeLocker;

    // An interface for the MapleGlobals contract.
    IGlobals private MapleGlobals;

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

    /// @notice The fee for stakers (in basis points).
    uint256 public stakingFee;

    /// @notice The fee for delegates (in basis points).
    uint256 public delegateFee;

    CalcBPool calcBPool; // TEMPORARY UNTIL LIBRARY IS SORTED OUT

    constructor(
        address _poolDelegate,
        address _liquidityAsset,
        address _stakeAsset,
        address _stakeLockerFactory,
        address _liquidityLockerFactory,
        uint256 _stakingFee,
        uint256 _delegateFee,
        string memory name,
        string memory symbol,
        address _mapleGlobals
    ) ERC20(name, symbol) public {
        require(
            address(_liquidityAsset) != address(0),
            "FDT_ERC20Extension: INVALID_FUNDS_TOKEN_ADDRESS"
        );

        // Assign variables relating to the LiquidityAsset.
        liquidityAsset = _liquidityAsset;
        liquidityAssetDecimals = ERC20(liquidityAsset).decimals();
        _ONELiquidityAsset = 10**(liquidityAssetDecimals);
        ILiquidityAsset = IERC20(_liquidityAsset);

        // Assign misc. state variables.
        stakeAsset = _stakeAsset;
        StakeLockerFactory = IStakeLockerFactory(_stakeLockerFactory);
        MapleGlobals = IGlobals(_mapleGlobals);
        poolDelegate = _poolDelegate;
        stakingFee = _stakingFee;
        delegateFee = _delegateFee;

        // Initialize the LiquidityLocker and StakeLocker.
        stakeLockerAddress = createStakeLocker(_stakeAsset);
        liquidityLockerAddress = address(
            ILiquidityLockerFactory(_liquidityLockerFactory).newLocker(liquidityAsset)
        );

        // Initialize Balancer pool calculator
        calcBPool = new CalcBPool();
    }

    modifier finalized() {
        require(isFinalized, "LiquidityPool:ERR_NOT_FINALIZED");
        _;
    }
    modifier notDefunct() {
        require(!isDefunct, "LiquidityPool:ERR_IS_DEFUNCT");
        _;
    }
    modifier isDelegate() {
        require(msg.sender == poolDelegate, "LiquidityPool:ERR_MSG_SENDER_NOT_DELEGATE");
        _;
    }

    function numFundedLoans() public view returns(uint) { return fundedLoans.length; }

    /// @notice Deploys and assigns a StakeLocker for this LiquidityPool.
    /// @param _stakeAsset Address of the asset used for staking.
    function createStakeLocker(address _stakeAsset) private returns (address) {
        require(
            IBPool(_stakeAsset).isBound(MapleGlobals.mapleToken()) &&
                IBPool(_stakeAsset).isFinalized(),
            "LiquidityPool::createStakeLocker:ERR_INVALID_BALANCER_POOL"
        );
        address _stakeLocker =
            StakeLockerFactory.newLocker(_stakeAsset, liquidityAsset, address(MapleGlobals));
        StakeLocker = IStakeLocker(_stakeLocker);
        return _stakeLocker;
    }

    /**
     * @notice Confirm poolDelegate's stake amount held in StakeLocker and finalize this LiquidityPool.
     */
    function finalize() public {
        (, , bool _stakePresent, , ) = getInitialStakeRequirements();
        require(_stakePresent, "LiquidityPool::finalize:ERR_NOT_ENOUGH_STAKE");
        isFinalized = true;
        StakeLocker.finalizeLP();
    }

    /**
        @notice Returns information on the stake requirements.
        @return uint, [0] = Amount of stake required.
        @return uint, [1] = Current swap out value of stake present.
        @return bool, [2] = If enough stake is present from Pool Delegate for finalization.
        @return uint, [3] = Amount of pool shares required.
        @return uint, [4] = Amount of pool shares present.
    */
    function getInitialStakeRequirements()
        public
        view
        returns (
            uint256,
            uint256,
            bool,
            uint256,
            uint256
        )
    {
        address pool = MapleGlobals.mapleBPool();
        address pair = MapleGlobals.mapleBPoolAssetPair();
        uint256 minStake = MapleGlobals.stakeAmountRequired();

        // TODO: Resolve the dissonance between poolSharesRequired / minstake / getSwapOutValue
        (uint256 _poolAmountInRequired, uint256 _poolAmountPresent) =
            calcBPool.getPoolSharesRequired(pool, pair, poolDelegate, stakeLockerAddress, minStake);
        return (
            minStake,
            calcBPool.getSwapOutValue(pool, pair, poolDelegate, stakeLockerAddress),
            calcBPool.getSwapOutValue(pool, pair, poolDelegate, stakeLockerAddress) >= minStake,
            _poolAmountInRequired,
            _poolAmountPresent
        );
    }

    // Note: Tether is unusable as a LiquidityAsset!
    /// @notice Liquidity providers can deposit LiqudityAsset into the LiquidityLocker, minting FDTs.
    /// @param _amt The amount of LiquidityAsset to deposit, in wei.
    function deposit(uint256 _amt) external notDefunct finalized {
        ILiquidityAsset.transferFrom(msg.sender, liquidityLockerAddress, _amt);
        uint256 _mintAmt = liq2FDT(_amt);
        _mint(msg.sender, _mintAmt);
    }

    function fundLoan(
        address _loanVault,
        address _loanTokenLockerFactory,
        uint256 _amt
    ) external notDefunct finalized isDelegate {
        // Auth check on loanVaultFactory "kernel"
        require(
            ILoanVaultFactory(MapleGlobals.loanVaultFactory()).isLoanVault(_loanVault),
            "LiquidityPool::fundLoan:ERR_LOAN_VAULT_INVALID"
        );
        // Instantiate locker if it doesn't exist with this factory type.
        if (loanTokenLockers[_loanVault][_loanTokenLockerFactory] == address(0)) {
            loanTokenLockers[_loanVault][_loanTokenLockerFactory] = ILoanTokenLockerFactory(
                _loanTokenLockerFactory
            ).newLocker(_loanVault);
            // Store data in fundedLoans array with a FundedLoan struct.
            fundedLoans.push(
                FundedLoan(
                    _loanVault, 
                    loanTokenLockers[_loanVault][_loanTokenLockerFactory],
                    _amt,
                    0,0,0,0
                )
            );
            // Emit event.
            emit LoanFunded(_loanVault, loanTokenLockers[_loanVault][_loanTokenLockerFactory], _amt);
        } else {
            
        }
        // Fund loan.
        ILiquidityLocker(liquidityLockerAddress).fundLoan(
            _loanVault,
            loanTokenLockers[_loanVault][_loanTokenLockerFactory],
            _amt
        );
    }

    /// @notice Claim available funds through a LoanToken.
    /// @param _id The index of FundedLoans to reference for claiming.
    /// @return uint[0]: Total amount claimed.
    ///         uint[1]: Principal portion claimed.
    ///         uint[2]: Interest portion claimed.
    ///         uint[3]: Fee portion claimed.
    ///         uint[4]: Excess portion claimed.
    ///         uint[5]: TODO: Liquidation portion claimed.
    function claim(uint256 _id) internal returns(uint, uint, uint, uint, uint/* TODO: uint*/) {

        // Grab "info" from fundedLoans data structure.
        FundedLoan memory info = fundedLoans[_id];

        // Create interface for LoanVault.
        ILoanVault vault = ILoanVault(info.loanVaultFunded);

        // Pull tokens from TokenLocker.
        ILoanTokenLocker(
            loanTokenLockers[info.loanVaultFunded][info.loanTokenLocker]
        ).fetch();

        // Calculate deltas, or "net new" values.
        uint256 newInterest  = vault.interestPaid() - info.interestPaid;
        uint256 newPrincipal = vault.principalPaid() - info.principalPaid;
        uint256 newFee       = vault.feePaid() - info.feePaid;
        uint256 newExcess    = vault.excessReturned() - info.excessReturned;

        // Update ERC2222 internal accounting for LoanVault.
        vault.updateFundsReceived();
        vault.withdrawFunds();

        // TODO: ERC-2222 could have return value in withdrawFunds(), 2 lines above.
        // Fetch amount claimed from calling withdrawFunds()
        uint256 balance = ILiquidityAsset.balanceOf(address(this));

        // Update "info" in fundedLoans data structure.
        info.interestPaid   = vault.interestPaid();
        info.principalPaid  = vault.principalPaid();
        info.feePaid        = vault.feePaid();
        info.excessReturned = vault.excessReturned();

        uint256 sum = newInterest.add(newPrincipal).add(newFee).add(newExcess);

        uint256 interest  = newInterest.mul(1 ether).div(sum).div(1 ether).mul(balance);
        uint256 principal = newPrincipal.mul(1 ether).div(sum).div(1 ether).mul(balance);
        uint256 fee       = newFee.mul(1 ether).div(sum).div(1 ether).mul(balance);
        uint256 excess    = newExcess.mul(1 ether).div(sum).div(1 ether).mul(balance);

        // Distribute "interest" to appropriate parties.
        uint256 toPoolDelegate    = interest.mul(delegateFee).div(10000);
        uint256 toStakeLocker     = interest.mul(stakingFee).div(10000);
        uint256 toLiquidityLocker = interest.mul(10000 - stakingFee - delegateFee).div(10000);

        require(ILiquidityAsset.transfer(poolDelegate,           toPoolDelegate));
        require(ILiquidityAsset.transfer(stakeLockerAddress,     toStakeLocker));
        require(ILiquidityAsset.transfer(liquidityLockerAddress, toLiquidityLocker));

        // Distribute "principal" and "excess" to liquidityLocker.
        require(ILiquidityAsset.transfer(liquidityLockerAddress, principal));
        require(ILiquidityAsset.transfer(liquidityLockerAddress, excess));

        // Distribute "fee" to poolDelegate.
        require(ILiquidityAsset.transfer(poolDelegate, fee));

        // Return tokens to locker.
        IERC20(info.loanVaultFunded).transfer(
            loanTokenLockers[info.loanVaultFunded][info.loanTokenLocker],
            IERC20(info.loanVaultFunded).balanceOf(address(this))
        );
    }

    /*these are to convert between FDT of 18 decim and liquidityasset locker of 0 to 256 decimals
    if we change the decimals on the FDT to match liquidityasset this would not be necessary
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
}
