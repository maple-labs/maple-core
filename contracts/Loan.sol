// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

import "./interfaces/ICollateralLocker.sol";
import "./interfaces/ICollateralLockerFactory.sol";
import "./interfaces/IERC20Details.sol";
import "./interfaces/IFundingLocker.sol";
import "./interfaces/IFundingLockerFactory.sol";
import "./interfaces/IGlobals.sol";
import "./interfaces/ILateFeeCalc.sol";
import "./interfaces/ILoanFactory.sol";
import "./interfaces/IPremiumCalc.sol";
import "./interfaces/IRepaymentCalc.sol";
import "./interfaces/IUniswapRouter.sol";
import "./library/Util.sol";
import "./library/LoanLib.sol";

import "./token/FDT.sol";

import "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/SafeERC20.sol";

/// @title Loan maintains all accounting and functionality related to Loans.
contract Loan is FDT, Pausable {
    
    using SafeMathInt     for int256;
    using SignedSafeMath  for int256;
    using SafeMath        for uint256;
    using SafeERC20       for IERC20;

    /**
        Live       = The loan has been initialized and is open for funding (assuming funding period not ended)
        Active     = The loan has been drawdown and the borrower is making payments
        Matured    = The loan is fully paid off and has "matured"
        Expired    = The loan did not initiate, and all funding was returned to lenders
        Liquidated = The loan has been liquidated
    */
    enum State { Live, Active, Matured, Expired, Liquidated }

    State public loanState;  // The current state of this loan, as defined in the State enum below

    IERC20 public immutable loanAsset;          // Asset deposited by lenders into the FundingLocker, when funding this loan
    IERC20 public immutable collateralAsset;    // Asset deposited by borrower into the CollateralLocker, for collateralizing this loan

    address public immutable fundingLocker;     // Funding locker - holds custody of loan funds before drawdown    
    address public immutable flFactory;         // Funding locker factory
    address public immutable collateralLocker;  // Collateral locker - holds custody of loan collateral
    address public immutable clFactory;         // Collateral locker factory
    address public immutable borrower;          // Borrower of this loan, responsible for repayments
    address public immutable repaymentCalc;     // The repayment calculator for this loan
    address public immutable lateFeeCalc;       // The late fee calculator for this loan
    address public immutable premiumCalc;       // The premium calculator for this loan
    address public immutable superFactory;      // The factory that deployed this Loan

    mapping(address => bool) public admins;  // Admin addresses that have permission to do certain operations in case of disaster mgt

    uint256 public nextPaymentDue;  // The unix timestamp due date of next payment

    // Loan specifications
    uint256 public immutable apr;                     // APR in basis points        
    uint256 public           paymentsRemaining;       // Number of payments remaining on the Loan
    uint256 public immutable termDays;                // Total length of the Loan term in days
    uint256 public immutable paymentIntervalSeconds;  // Time between Loan payments in seconds
    uint256 public immutable requestAmount;           // Total requested amount for Loan
    uint256 public immutable collateralRatio;         // Percentage of value of drawdown amount to post as collateral in basis points
    uint256 public immutable fundingPeriodSeconds;    // Time for a Loan to be funded in seconds
    uint256 public immutable createdAt;               // Timestamp of when Loan was instantiated

    // Accounting variables
    uint256 public principalOwed;   // The principal owed (initially the drawdown amount)
    uint256 public principalPaid;   // Amount of principal  that has been paid by borrower since Loan instantiation
    uint256 public interestPaid;    // Amount of interest   that has been paid by borrower since Loan instantiation
    uint256 public feePaid;         // Amount of fees      that have been paid by borrower since Loan instantiation
    uint256 public excessReturned;  // Amount of excess that has been returned to lenders after Loan drawdown
    
    // Liquidation variables
    uint256 public amountLiquidated;   // Amount of collateral that has been liquidated after default
    uint256 public amountRecovered;    // Amount of loanAsset  that has been recovered  after default
    uint256 public defaultSuffered;    // Difference between `amountRecovered` and `principalOwed` after liquidation
    uint256 public liquidationExcess;  // If `amountRecovered > principalOwed`, amount of loanAsset that is to be returned to borrower

    event LoanFunded(uint256 amtFunded, address indexed _fundedBy);
    event BalanceUpdated(address who, address token, uint256 balance);
    event Drawdown(uint256 drawdownAmt);
    event PaymentMade(
        uint totalPaid,
        uint principalPaid,
        uint interestPaid,
        uint paymentsRemaining,
        uint principalOwed,
        uint nextPaymentDue,
        bool latePayment
    );
    event Liquidation(
        uint collateralSwapped,
        uint loanAssetReturned,
        uint liquidationExcess,
        uint defaultSuffered
    );

    /**
        @dev Constructor for a Loan.
        @param  _borrower        Will receive the funding when calling drawdown(), is also responsible for repayments
        @param  _loanAsset       The asset _borrower is requesting funding in
        @param  _collateralAsset The asset provided as collateral by _borrower
        @param  _flFactory       Factory to instantiate FundingLocker with
        @param  _clFactory       Factory to instantiate CollateralLocker with
        @param  specs            Contains specifications for this loan
                specs[0] = apr
                specs[1] = termDays
                specs[2] = paymentIntervalDays (aka PID)
                specs[3] = requestAmount
                specs[4] = collateralRatio
                specs[5] = fundingPeriodDays
        @param  calcs The calculators used for the loan
                calcs[0] = repaymentCalc
                calcs[1] = lateFeeCalc
                calcs[2] = premiumCalc
    */
    constructor(
        address _borrower,
        address _loanAsset,
        address _collateralAsset,
        address _flFactory,
        address _clFactory,
        uint256[6] memory specs,
        address[3] memory calcs
    )
        FDT(
            string(abi.encodePacked("Maple Loan Token")),
            string(abi.encodePacked("MPL-LOAN")),
            _loanAsset
        )
        public
    {
        IGlobals globals = _globals(msg.sender);

        // Perform validity cross-checks
        require(globals.isValidLoanAsset(_loanAsset),             "Loan:INVALID_LOAN_ASSET");
        require(globals.isValidCollateralAsset(_collateralAsset), "Loan:INVALID_COLLATERAL_ASSET");

        require(specs[2] != uint256(0),               "Loan:PID_EQ_ZERO");
        require(specs[1].mod(specs[2]) == uint256(0), "Loan:INVALID_TERM_DAYS");
        require(specs[3] > uint256(0),                "Loan:REQUEST_AMT_EQ_ZERO");
        require(specs[5] > uint256(0),                "Loan:FUNDING_PERIOD_EQ_ZERO");

        borrower        = _borrower;
        loanAsset       = IERC20(_loanAsset);
        collateralAsset = IERC20(_collateralAsset);
        flFactory       = _flFactory;
        clFactory       = _clFactory;
        createdAt       = block.timestamp;

        // Update state variables
        apr                    = specs[0];
        termDays               = specs[1];
        paymentsRemaining      = specs[1].div(specs[2]);
        paymentIntervalSeconds = specs[2].mul(1 days);
        requestAmount          = specs[3];
        collateralRatio        = specs[4];
        fundingPeriodSeconds   = specs[5].mul(1 days);
        repaymentCalc          = calcs[0];
        lateFeeCalc            = calcs[1];
        premiumCalc            = calcs[2];
        superFactory           = msg.sender;

        // Deploy lockers
        collateralLocker = ICollateralLockerFactory(_clFactory).newLocker(_collateralAsset);
        fundingLocker    = IFundingLockerFactory(_flFactory).newLocker(_loanAsset);
    }

    /**************************/
    /*** Borrower Functions ***/
    /**************************/

    /**
        @dev Drawdown funding from FundingLocker, post collateral, and transition loanState from Funding to Active.
        @param amt Amount of loanAsset borrower draws down, remainder is returned to Loan where it can be claimed back by LoanFDT holders.
    */
    function drawdown(uint256 amt) external {
        _whenProtocolNotPaused();
        _isValidBorrower();
        _isValidState(State.Live);
        IGlobals globals = _globals(superFactory);

        IFundingLocker _fundingLocker = IFundingLocker(fundingLocker);

        require(amt >= requestAmount,              "Loan:AMT_LT_REQUEST_AMT");
        require(amt <= _getFundingLockerBalance(), "Loan:AMT_GT_FUNDED_AMT");

        // Update accounting variables for Loan
        principalOwed  = amt;
        nextPaymentDue = block.timestamp.add(paymentIntervalSeconds);

        loanState = State.Active;

        // Transfer the required amount of collateral for drawdown from Borrower to CollateralLocker.
        collateralAsset.safeTransferFrom(borrower, collateralLocker, collateralRequiredForDrawdown(amt));

        // Transfer funding amount from FundingLocker to Borrower, then drain remaining funds to Loan.
        uint256 treasuryFee = globals.treasuryFee();
        uint256 investorFee = globals.investorFee();

        address treasury = globals.mapleTreasury();

        uint256 _feePaid = feePaid = amt.mul(investorFee).div(10000);  // Update fees paid for claim()
        uint256 treasuryAmt        = amt.mul(treasuryFee).div(10000);  // Calculate amt to send to MapleTreasury

        _transferFunds(_fundingLocker, treasury, treasuryAmt);                         // Send treasuryFee directly to MapleTreasury
        _transferFunds(_fundingLocker, borrower, amt.sub(treasuryAmt).sub(_feePaid));  // Transfer drawdown amount to Borrower

        // Update excessReturned for claim()
        excessReturned = _getFundingLockerBalance().sub(_feePaid);

        // Drain remaining funds from FundingLocker (amount equal to excessReturned plus feePaid)
        _fundingLocker.drain();

        // Call updateFundsReceived() update FDT accounting with funds recieved from fees and excess returned
        updateFundsReceived();

        _emitBalanceUpdateEventForCollateralLocker();
        _emitBalanceUpdateEventForFundingLocker();
        _emitBalanceUpdateEventForLoan();

        emit BalanceUpdated(treasury, address(loanAsset), loanAsset.balanceOf(treasury));
        
        emit Drawdown(amt);
    }

    /**
        @dev Make a payment for the Loan. Amounts are calculated for the borrower.
    */
    function makePayment() external {
        _whenProtocolNotPaused();
        _isValidState(State.Active);
        (uint256 total, uint256 principal, uint256 interest,, bool paymentLate) = getNextPayment();
        paymentsRemaining--;
        _makePayment(total, principal, interest, paymentLate);
    }

    /**
        @dev Make the full payment for this loan, a.k.a. "calling" the loan. This requires the borrower to pay a premium.
    */
    function makeFullPayment() public {
        _whenProtocolNotPaused();
        _isValidState(State.Active);
        (uint256 total, uint256 principal, uint256 interest) = getFullPayment();
        paymentsRemaining = uint256(0);
        _makePayment(total, principal, interest, false);
    }

    /**
        @dev Internal function to update the payment variables and transfer funds from the borrower into the Loan.
    */
    function _makePayment(uint256 total, uint256 principal, uint256 interest, bool paymentLate) internal {

        loanAsset.safeTransferFrom(msg.sender, address(this), total);

        // Caching it to reduce the `SLOADS`.
        uint256 _paymentsRemaining = paymentsRemaining;
        // Update internal accounting variables.
        if (_paymentsRemaining == uint256(0)) {
            principalOwed  = uint256(0);
            loanState      = State.Matured;
            nextPaymentDue = uint256(0);
        } else {
            principalOwed  = principalOwed.sub(principal);
            nextPaymentDue = nextPaymentDue.add(paymentIntervalSeconds);
        }
        principalPaid = principalPaid.add(principal);
        interestPaid  = interestPaid.add(interest);

        // Call updateFundsReceived() update FDT accounting with funds recieved from interest payment
        updateFundsReceived(); 

        emit PaymentMade(
            total, 
            principal, 
            interest, 
            _paymentsRemaining, 
            principalOwed, 
            _paymentsRemaining > 0 ? nextPaymentDue : 0, 
            paymentLate
        );

        // Handle final payment.
        if (_paymentsRemaining == 0) {
            // Transferring all collaterised funds back to the borrower
            ICollateralLocker(collateralLocker).pull(borrower, _getCollateralLockerBalance());
            _emitBalanceUpdateEventForCollateralLocker();
        }
        _emitBalanceUpdateEventForLoan();
    }

    /************************/
    /*** Lender Functions ***/
    /************************/

    /**
        @dev Fund this loan and mint LoanFDTs for mintTo (DebtLocker in the case of Pool funding)
        @param  amt    Amount to fund the loan
        @param  mintTo Address that LoanFDTs are minted to
    */
    function fundLoan(address mintTo, uint256 amt) whenNotPaused external {
        _whenProtocolNotPaused();
        _isValidState(State.Live);
        loanAsset.safeTransferFrom(msg.sender, fundingLocker, amt);

        uint256 wad = _toWad(amt);  // Convert to WAD precision
        _mint(mintTo, wad);         // Mint FDT to `mintTo` i.e DebtLocker contract.

        emit LoanFunded(amt, mintTo);
        _emitBalanceUpdateEventForFundingLocker();
    }

    /**
        @dev If the borrower has not drawn down on the Loan past the drawdown grace period, return capital to Loan, 
             where it can be claimed back by LoanFDT holders.
    */
    function unwind() external {
        _whenProtocolNotPaused();
        _isValidState(State.Live);

        // Update accounting for claim(), transfer funds from FundingLocker to Loan
        excessReturned = LoanLib.unwind(loanAsset, superFactory, fundingLocker, createdAt);

        updateFundsReceived();

        // Transition state to Expired
        loanState = State.Expired;
    }

    /**
        @dev Trigger a default if a Loan is in a condition where a default can be triggered, liquidating all collateral and updating accounting.
    */
    // TODO: Talk with auditors about having a switch for this function
    function triggerDefault() external {
        _whenProtocolNotPaused();
        _isValidState(State.Active);
        require(LoanLib.canTriggerDefault(nextPaymentDue, superFactory, balanceOf(msg.sender), totalSupply()), "Loan:FAILED_TO_LIQUIDATE");
        
        (amountLiquidated, amountRecovered) = LoanLib.triggerDefault(collateralAsset, address(loanAsset), superFactory, collateralLocker);

        // Set principalOwed to zero and return excess value from liquidation back to borrower
        if (amountRecovered > principalOwed) {
            liquidationExcess = amountRecovered.sub(principalOwed);
            principalOwed = 0;
            loanAsset.safeTransfer(borrower, liquidationExcess); // Send excess to Borrower.
        }
        // Decrement principalOwed by amountRecovered, set defaultSuffered to the difference (shortfall from liquidation)
        else {
            principalOwed   = principalOwed.sub(amountRecovered);
            defaultSuffered = principalOwed;
        }

        // Call updateFundsReceived() update FDT accounting with funds recieved from liquidation
        updateFundsReceived();

        // Transition loanState to Liquidated
        loanState = State.Liquidated;

        // Emit liquidation event
        emit Liquidation(
            amountLiquidated,  // Amount of collateralAsset swapped
            amountRecovered,   // Amount of loanAsset recovered from swap
            liquidationExcess, // Amount of loanAsset returned to borrower
            defaultSuffered    // Remaining losses after liquidation
        );
    }

    /***********************/
    /*** Admin Functions ***/
    /***********************/

    /**
        @dev Triggers paused state. Halts functionality for certain functions.
    */
    function pause() external { 
        _isValidBorrowerOrAdmin();
        super._pause();
    }

    /**
        @dev Triggers unpaused state. Returns functionality for certain functions.
    */
    function unpause() external {
        _isValidBorrowerOrAdmin();
        super._unpause();
    }

    /**
        @dev Set admin.
        @param newAdmin New admin address
        @param allowed  Status of an admin
    */
    function setAdmin(address newAdmin, bool allowed) external {
        _whenProtocolNotPaused();
        _isValidBorrower();
        admins[newAdmin] = allowed;
    }

    /**************************/
    /*** Governor Functions ***/
    /**************************/

    /**
        @dev Transfer any locked funds to the governor.
        @param token Address of the token that need to reclaimed.
     */
    function reclaimERC20(address token) external {
        LoanLib.reclaimERC20(token, address(loanAsset), _globals(superFactory));
    }

    /*********************/
    /*** FDT Functions ***/
    /*********************/

    /**
        @dev Withdraws all available funds earned through FDT for a token holder.
    */
    function withdrawFunds() public override {
        _whenProtocolNotPaused();
        super.withdrawFunds();
    }

    /************************/
    /*** Getter Functions ***/
    /************************/

    /**
        @dev Public getter to know how much minimum amount of loan asset will get by swapping collateral asset.
        @return Expected amount of loanAsset to be recovered from liquidation based on current oracle prices
    */
    function getExpectedAmountRecovered() public view returns(uint256) {
        uint256 liquidationAmt = _getCollateralLockerBalance();
        return Util.calcMinAmount(_globals(superFactory), address(collateralAsset), address(loanAsset), liquidationAmt);
    }
    
    /**
        @dev Returns information on next payment amount.
        @return [0] = Principal + Interest
                [1] = Principal 
                [2] = Interest
                [3] = Payment Due Date
                [4] = Is Payment Late
    */
    function getNextPayment() public view returns(uint256, uint256, uint256, uint256, bool) {
        return LoanLib.getNextPayment(superFactory, repaymentCalc, nextPaymentDue, lateFeeCalc);
    }

    /**
        @dev Returns information on full payment amount.
        @return total     Principal and interest owed, combined
        @return principal Principal owed
        @return interest  Interest owed
    */
    function getFullPayment() public view returns(uint256 total, uint256 principal, uint256 interest) {
        (total, principal, interest) = IPremiumCalc(premiumCalc).getPremiumPayment(address(this));
    }

    /**
        @dev Helper for calculating collateral required to draw down amt.
        @param  amt The amount of loanAsset to draw down from FundingLocker
        @return The amount of collateralAsset required to post in CollateralLocker for given drawdown amt.
    */
    function collateralRequiredForDrawdown(uint256 amt) public view returns(uint256) {
        return LoanLib.collateralRequiredForDrawdown(
            IERC20Details(address(collateralAsset)),
            IERC20Details(address(loanAsset)),
            collateralRatio,
            superFactory,
            amt
        );
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    /**
        @dev Function to block functionality of functions when protocol is in a paused state.
    */
    function _whenProtocolNotPaused() internal {
        require(!_globals(superFactory).protocolPaused(), "Loan:PROTOCOL_PAUSED");
    }

    /**
        @dev Function to determine if msg.sender is eligible to trigger pause/unpause.
    */
    function _isValidBorrowerOrAdmin() internal {
        require(msg.sender == borrower || admins[msg.sender], "Pool:UNAUTHORIZED");
    }

    /**
        @dev Utility to convert to WAD precision.
    */
    function _toWad(uint256 amt) internal view returns(uint256) {
        return amt.mul(10 ** 18).div(10 ** IERC20Details(address(loanAsset)).decimals());
    }

    /**
        @dev Utility to return MapleGlobals interface.
    */
    function _globals(address loanFactory) internal view returns (IGlobals) {
        return IGlobals(ILoanFactory(loanFactory).globals());
    }

    /**
        @dev Utility to return CollateralLocker balance.
    */
    function _getCollateralLockerBalance() internal view returns (uint256) {
        return collateralAsset.balanceOf(collateralLocker);
    }

    /**
        @dev Utility to return FundingLocker balance.
    */
    function _getFundingLockerBalance() internal view returns (uint256) {
        return loanAsset.balanceOf(fundingLocker);
    }

    /**
        @dev Utility to check current state of Loan againt provided state.
        @param _state Enum of desired Loan state
    */
    function _isValidState(State _state) internal view {	
        require(loanState == _state, "Loan:INVALID_STATE");	
    }	

    /**
        @dev Utility to return if msg.sender is the Loan borrower.
    */
    function _isValidBorrower() internal view {	
        require(msg.sender == borrower, "Loan:INVALID_BORROWER");	
    }

    /**
        @dev Utility to transfer funds from the FundingLocker.
        @param from  Interface of the FundingLocker
        @param to    Address to send funds to
        @param value Amount to send
    */
    function _transferFunds(IFundingLocker from, address to, uint256 value) internal {
        from.pull(to, value);
    }

    /**
        @dev Utility to emit BalanceUpdated event for Loan.
    */
    function _emitBalanceUpdateEventForLoan() internal {
        emit BalanceUpdated(address(this), address(loanAsset), loanAsset.balanceOf(address(this)));
    }

    /**
        @dev Utility to emit BalanceUpdated event for FundingLocker.
    */
    function _emitBalanceUpdateEventForFundingLocker() internal {
        emit BalanceUpdated(fundingLocker, address(loanAsset), _getFundingLockerBalance());
    }

    /**
        @dev Utility to emit BalanceUpdated event for CollateralLocker.
    */
    function _emitBalanceUpdateEventForCollateralLocker() internal {
        emit BalanceUpdated(collateralLocker, address(collateralAsset), _getCollateralLockerBalance());
    }
}
