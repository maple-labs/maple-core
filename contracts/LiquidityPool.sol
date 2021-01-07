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

    uint256 constant WAD = 10 ** 18;

    address public immutable poolDelegate;            // The pool delegate, who maintains full authority over this LiquidityPool. (TODO: Should this be immutable?)
    address public immutable liquidityLockerAddress;  // The LiquidityLocker owned by this contract.
    address public immutable stakeAsset;              // The asset deposited by stakers into the StakeLocker, for liquidation during default events.
    address public immutable stakeLockerAddress;      // Address of the StakeLocker, escrowing the staked asset.
    address public           liquidityAsset;          // The asset deposited by lenders into the LiquidityLocker, for funding loans. (TODO: Make immutable)

    uint8   private           liquidityAssetDecimals;  // decimals() precision for the liquidityAsset. (TODO: Examine the use of this variable, make immutable)
    uint256 private immutable ONELiquidityAsset;       // 10^k where k = liquidityAssetDecimals, representing one LiquidityAsset unit in 'wei'. (TODO: Examine the use of this variable)

    IStakeLockerFactory private StakeLockerFactory;  // An interface for the factory used to instantiate a StakeLocker for this LiquidityPool.
    IERC20              private ILiquidityAsset;     // An interface for this contract's liquidity asset, stored in two separate variables.
    IERC20              private IStakeAsset;         // An interface for the asset used to stake the StakeLocker for this LiquidityPool.
    IStakeLocker        private StakeLocker;         // An interface for the locker which escrows StakeAsset.
    IGlobals            private MapleGlobals;        // An interface for the MapleGlobals contract.

    uint256 public principalSum;  // Sum of all outstanding principal on loans
    uint256 public interestSum; //sum of all interest currently inside the liquidity locker
    uint256 public stakingFee;    // The fee for stakers (in basis points).
    uint256 public delegateFee;   // The fee for delegates (in basis points).
    uint256 public interestDelay = 30 days; // delay on interest claim

    bool public isFinalized;  // True if this LiquidityPool is setup and the poolDelegate has met staking requirements.
    bool public isDefunct;    // True when the pool is closed, enabling poolDelegate to withdraw their stake.
    mapping (address => uint256) public depositAge; //used for interest penalty calculation
    mapping(address => mapping(address => address)) public loanTokenLockers;  // loans[LOAN_VAULT][LOCKER_FACTORY] = loanTokenLocker

    CalcBPool calcBPool; // TEMPORARY UNTIL LIBRARY IS SORTED OUT

    event LoanFunded(address loanVaultFunded, address loanTokenLocker, uint256 amountFunded);
    event BalanceUpdated(address who, address token, uint256 balance);
    event Claim(uint interest, uint principal, uint fee);

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
        ONELiquidityAsset = 10 ** (liquidityAssetDecimals);
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
        _updateDepositAge(_amt, msg.sender);
        _mint(msg.sender, _mintAmt);

        emit BalanceUpdated(liquidityLockerAddress, address(ILiquidityAsset), ILiquidityAsset.balanceOf(liquidityLockerAddress));
    }

    function withdraw(uint256 _amt) external notDefunct finalized {
        require(balanceOf(msg.sender) >= _amt, "LiquidityPool::withdraw:USER_BAL_LESS_THAN_AMT");
        uint256 share = _amt.mul(WAD).div(totalSupply());
        uint256 bal   = IERC20(liquidityAsset).balanceOf(liquidityLockerAddress);
        uint256 due   = share.mul(principalSum.add(bal)).div(WAD);
	uint256 _interestRatio = WAD.mul(interestSum).div(principalSum.add(bal));//interest/totalMoney
        uint256 _myInterest = due.mul(_interestRatio).div(WAD);//get nominal interest owned by sender
        uint256 _penalty = calcInterestPenalty(_myInterest, msg.sender); //get penalty, however it may be calculated
        due = due.sub(_penalty);//remove penalty
        interestSum = interestSum.sub(_myInterest).add(_penalty);//update interest total reflecting withdrawn ammount
        _burn(msg.sender, _amt); // TODO: Unit testing on _burn / _mint for ERC-2222
        require(ILiquidityLocker(liquidityLockerAddress).transfer(msg.sender, due), "LiquidityPool::ERR_WITHDRAW_TRANSFER");
        emit BalanceUpdated(liquidityLockerAddress, address(ILiquidityAsset), ILiquidityAsset.balanceOf(liquidityLockerAddress));
    }

    function fundLoan(
        address _vault,
        address _ltlFactory,
        uint256 _amount
    ) external notDefunct finalized isDelegate {

        // Auth check on loanVaultFactory "kernel"
        require(
            ILoanVaultFactory(MapleGlobals.loanVaultFactory()).isLoanVault(_vault),
            "LiquidityPool::fundLoan:ERR_LOAN_VAULT_INVALID"
        );

        // Instantiate locker if it doesn't exist with this factory type.
        if (loanTokenLockers[_vault][_ltlFactory] == address(0)) {
            address _loanTokenLocker = ILoanTokenLockerFactory(_ltlFactory).newLocker(_vault);
            loanTokenLockers[_vault][_ltlFactory] = _loanTokenLocker;
        }
        
        principalSum += _amount;

        // Fund loan.
        ILiquidityLocker(liquidityLockerAddress).fundLoan(
            _vault,
            loanTokenLockers[_vault][_ltlFactory],
            _amount
        );
        
        emit LoanFunded(_vault, loanTokenLockers[_vault][_ltlFactory], _amount);
        emit BalanceUpdated(liquidityLockerAddress, address(ILiquidityAsset), ILiquidityAsset.balanceOf(liquidityLockerAddress));
    }

    /// @notice Claim available funds through a LoanToken.
    /// @return uint[0]: Total amount claimed.
    ///         uint[1]: Interest portion claimed.
    ///         uint[2]: Principal portion claimed.
    ///         uint[3]: Fee portion claimed.
    ///         uint[4]: Excess portion claimed.
    ///         uint[5]: TODO: Liquidation portion claimed.
    function claim(address _vault, address _ltlFactory) public returns(uint[5] memory) { 
        
        uint[5] memory claimInfo = ILoanTokenLocker(loanTokenLockers[_vault][_ltlFactory]).claim();

        // Distribute "interest" to appropriate parties.
        require(ILiquidityAsset.transfer(poolDelegate,       claimInfo[1].mul(delegateFee).div(10000)));
        require(ILiquidityAsset.transfer(stakeLockerAddress, claimInfo[1].mul(stakingFee).div(10000)));

        // Distribute "fee" to poolDelegate.
        require(ILiquidityAsset.transfer(poolDelegate, claimInfo[3]));

        // Transfer remaining balance (remaining interest + principal + excess + rounding error) to liqudityLocker
        uint remainder = ILiquidityAsset.balanceOf(address(this));
        require(ILiquidityAsset.transfer(liquidityLockerAddress, remainder));

        // Update outstanding principal, the interest distribution mechanism.
        principalSum = principalSum.sub(claimInfo[2]).sub(claimInfo[4]); // Reversion here indicates critical error.
        interestSum = interestSum.add(claimInfo[1]);
        // TODO: Consider any underflow / overflow that feeds into this calculation from RepaymentCalculators.

        // Update funds received for ERC-2222 StakeLocker tokens.
        StakeLocker.updateFundsReceived();

        emit BalanceUpdated(liquidityLockerAddress, address(ILiquidityAsset), ILiquidityAsset.balanceOf(liquidityLockerAddress));
        emit BalanceUpdated(stakeLockerAddress,     address(ILiquidityAsset), ILiquidityAsset.balanceOf(stakeLockerAddress));
        emit BalanceUpdated(poolDelegate,           address(ILiquidityAsset), ILiquidityAsset.balanceOf(poolDelegate));

        emit Claim(claimInfo[1], claimInfo[2] + claimInfo[4], claimInfo[3]);

        return claimInfo;
    }
    /** This is to establish the function signatur by which an interest penalty will be calculated
    The resulting value will be removed from the interest used in a repayment
    **/
    function calcInterestPenalty(uint256 _interest, address _addy) public view returns (uint256 _out){
        uint256 _time = (block.timestamp.sub(depositAge[_addy])).mul(WAD);
        uint256 _unlocked = ((_time.div(interestDelay+1)).mul(_interest)) / WAD;
        if (_unlocked > _interest) {
            _out = 0;
        }else{
            _out = _interest - _unlocked;  
        }
        return _out;
    }

    function _updateDepositAge(uint256 _amt, address _addy) internal {
        if (depositAge[_addy] == 0) {
            depositAge[_addy] = block.timestamp;
        } else {
            uint256 _date = depositAge[_addy];
            uint256 _coef = (WAD.mul(_amt)).div(balanceOf(_addy).add(_amt)); //yes, i want 0 if _amt is too small
            //thhis addition will start to overflow in about 3^52 years
            depositAge[_addy] = ( _date.mul(WAD).add((block.timestamp.sub(_date)).mul(_coef)) ).div(WAD);
        }
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
            uint _offset = 18 - liquidityAssetDecimals;
            _out = _amt.mul(10 ** _offset);
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
