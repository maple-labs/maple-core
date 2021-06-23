// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

/// @title MapleGlobals maintains a central source of parameters and allowlists for the Maple protocol.
interface IMapleGlobals {

    /**
        @dev   Emits an event indicating the MapleGlobals contract was created.
     */
    event Initialized();

    /**
        @dev   Emits an event indicating the validity of a Collateral Asset was set.
        @param asset    The Collateral Asset to assign validity to.
        @param decimals The number of decimal places of `asset`.
        @param symbol   The symbol of `asset`.
        @param valid    The new validity status of `asset`.
     */
    event CollateralAssetSet(address asset, uint256 decimals, string symbol, bool valid);

    /**
        @dev   Emits an event indicating the validity of a Liquidity Asset was set.
        @param asset    The Liquidity Asset to assign validity to.
        @param decimals The number of decimal places of `asset`.
        @param symbol   The symbol of `asset`.
        @param valid    The new validity status of `asset`.
     */
    event LiquidityAssetSet(address asset, uint256 decimals, string symbol, bool valid);

    /**
        @dev   Emits an event indicating the Oracle for an asset was set.
        @param asset  The asset to update price for.
        @param oracle The new Oracle to use.
     */
    event OracleSet(address asset, address oracle);

    /**
        @dev This is unused.
     */
    event TransferRestrictionExemptionSet(address indexed exemptedContract, bool valid);

    /**
        @dev   Emits an event indicating the validity of a Balancer Pool was set.
        @param balancerPool The address of Balancer Pool contract.
        @param valid        The new validity status of a Balancer Pool.
     */
    event BalancerPoolSet(address balancerPool, bool valid);

    /**
        @dev   Emits an event indicating a PendingGovernor was set.
        @param pendingGovernor The address of the new Pending Governor.
     */
    event PendingGovernorSet(address indexed pendingGovernor);

    /**
        @dev   Emits an event indicating Governorship was accepted by a new account.
        @param governor The account that has accepted Governorship.
     */
    event GovernorAccepted(address indexed governor);

    /**
        @dev   Emits an event indicating that some Governor controlled parameter was set.
        @param which The identifier of the parameter that was set.
        @param value The value the parameter was set to.
     */
    event GlobalsParamSet(bytes32 indexed which, uint256 value);

    /**
        @dev   Emits an event indicating that some Governor controlled address was set.
        @param which The identifier of the address that was set.
        @param addr  The address that was set.
     */
    event GlobalsAddressSet(bytes32 indexed which, address addr);

    /**
        @dev   Emits an event indicating the protocol's paused state has been set.
        @param pause Whether the protocol was paused.
     */
    event ProtocolPaused(bool pause);

    /**
        @dev   Emits an event indicating the GlobalAdmin was set.
        @param newGlobalAdmin The address of the new GlobalAdmin.
     */
    event GlobalAdminSet(address indexed newGlobalAdmin);

    /**
        @dev   Emits an event indicating the validity of a Pool Delegate was set.
        @param poolDelegate The address of a Pool Delegate.
        @param valid        Whether `poolDelegate` is a valid Pool Delegate.
     */
    event PoolDelegateSet(address indexed poolDelegate, bool valid);

    /**
        @dev The ERC-2222 Maple Token for the Maple protocol.
     */
    function mpl() external pure returns (address);

    /**
        @dev The Governor that is declared for governorship transfer. 
        @dev Must be accepted for transfer to take effect. 
     */
    function pendingGovernor() external view returns (address);

    /**
        @dev The Governor responsible for management of global Maple variables.
     */
    function governor() external view returns (address);

    /**
        @dev The MapleTreasury is the Treasury where all fees pass through for conversion, prior to distribution.
     */
    function mapleTreasury() external view returns (address);

    /**
        @dev The Global Admin of the whole network. 
        @dev Has the power to switch off/on the functionality of entire protocol. 
     */
    function globalAdmin() external view returns (address);

    /**
        @dev The amount of time a Borrower has to make a missed payment before a default can be triggered. 
     */
    function defaultGracePeriod() external view returns (uint256);

    /**
        @dev The minimum amount of Pool cover that a Pool Delegate has to provide before they can finalize a Pool.
     */
    function swapOutRequired() external view returns (uint256);

    /**
        @dev The amount of time to allow a Borrower to drawdown on their Loan after funding period ends.
     */
    function fundingPeriod() external view returns (uint256);

    /**
        @dev The portion of drawdown that goes to the Pool Delegates and individual Lenders.
     */
    function investorFee() external view returns (uint256);

    /**
        @dev The portion of drawdown that goes to the MapleTreasury.
     */
    function treasuryFee() external view returns (uint256);

    /**
        @dev The maximum amount of slippage for Uniswap transactions.
     */
    function maxSwapSlippage() external view returns (uint256);

    /**
        @dev The minimum amount of LoanFDTs required to trigger liquidations (basis points percentage of totalSupply).
     */
    function minLoanEquity() external view returns (uint256);

    /**
        @dev The period (in secs) after which Stakers are allowed to unstake their BPTs from a StakeLocker.
     */
    function stakerCooldownPeriod() external view returns (uint256);

    /**
        @dev The period (in secs) after which LPs are allowed to withdraw their funds from a Pool.
     */
    function lpCooldownPeriod() external view returns (uint256);

    /**
        @dev The window of time (in secs) after `stakerCooldownPeriod` that an account has to withdraw before their intent to unstake is invalidated.
     */
    function stakerUnstakeWindow() external view returns (uint256);

    /**
        @dev The window of time (in secs) after `lpCooldownPeriod` that an account has to withdraw before their intent to withdraw is invalidated.
     */
    function lpWithdrawWindow() external view returns (uint256);

    /**
        @dev Whether the functionality of the entire protocol is paused.
     */
    function protocolPaused() external view returns (bool);

    /**
        @param  liquidityAsset The address of a Liquidity Asset.
        @return Whether `liquidityAsset` is valid.
     */
    function isValidLiquidityAsset(address liquidityAsset) external view returns (bool);

    /**
        @param  collateralAsset The address of a Collateral Asset.
        @return Whether `collateralAsset` is valid.
     */
    function isValidCollateralAsset(address collateralAsset) external view returns (bool);

    /**
        @param  calc The address of a Calculator.
        @return Whether `calc` is valid.
     */
    function validCalcs(address calc) external view returns (bool);

    /**
        @dev    Prevents unauthorized/unknown addresses from creating Pools.
        @param  poolDelegate The address of a Pool Delegate.
        @return Whether `poolDelegate` is valid.
     */
    function isValidPoolDelegate(address poolDelegate) external view returns (bool);

    /**
        @param  balancerPool The address of a Balancer Pool.
        @return Whether Maple has approved `balancerPool` for BPT staking.
     */
    function isValidBalancerPool(address balancerPool) external view returns (bool);

    /**
        @dev Determines the liquidation path of various assets in Loans and the Treasury. 
        @dev The value provided will determine whether or not to perform a bilateral or triangular swap on Uniswap. 
        @dev For example, `defaultUniswapPath[WBTC][USDC]` value would indicate what asset to convert WBTC into before conversion to USDC. 
        @dev If `defaultUniswapPath[WBTC][USDC] == USDC`, then the swap is bilateral and no middle asset is swapped. 
        @dev If `defaultUniswapPath[WBTC][USDC] == WETH`, then swap WBTC for WETH, then WETH for USDC. 
        @param  tokenA The address of the asset being swapped.
        @param  tokenB The address of the final asset to receive.
        @return The intermediary asset for swaps, if any.
     */
    function defaultUniswapPath(address tokenA, address tokenB) external view returns (address);

    /**
        @param  asset The address of some token.
        @return The Chainlink Oracle for the price of `asset`.
     */
    function oracleFor(address asset) external view returns (address);
    
    /**
        @param  poolFactory The address of a Pool Factory.
        @return Whether `poolFactory` is valid.
     */
    function isValidPoolFactory(address poolFactory) external view returns (bool);

    /**
        @param  loanFactory The address of a Loan Factory.
        @return Whether `loanFactory` is valid.
     */
    function isValidLoanFactory(address loanFactory) external view returns (bool);
    
    /**
        @param  superFactory The core factory (e.g. PoolFactory, LoanFactory).
        @param  subFactory   The sub factory used by core factory (e.g. LiquidityLockerFactory).
        @return Whether `subFactory` is valid as it relates to `superFactory`.
     */
    function validSubFactories(address superFactory, address subFactory) external view returns (bool);
    
    /**
        @dev   Sets the Staker cooldown period. 
        @dev   This change will affect the existing cool down period for the Stakers that already intended to unstake. 
        @dev   Only the Governor can call this function. 
        @dev   It emits a `GlobalsParamSet` event. 
        @param newCooldownPeriod The new value for the cool down period.
     */
    function setStakerCooldownPeriod(uint256 newCooldownPeriod) external;

    /**
        @dev   Sets the Liquidity Pool cooldown period. 
        @dev   This change will affect the existing cool down period for the LPs that already intended to withdraw. 
        @dev   Only the Governor can call this function. 
        @dev   It emits a `GlobalsParamSet` event. 
        @param newCooldownPeriod The new value for the cool down period.
     */
    function setLpCooldownPeriod(uint256 newCooldownPeriod) external;

    /**
        @dev   Sets the Staker unstake window. 
        @dev   This change will affect the existing window for the Stakers that already intended to unstake. 
        @dev   Only the Governor can call this function. 
        @dev   It emits a `GlobalsParamSet` event. 
        @param newUnstakeWindow The new value for the unstake window.
     */
    function setStakerUnstakeWindow(uint256 newUnstakeWindow) external;

    /**
        @dev   Sets the Liquidity Pool withdraw window. 
        @dev   This change will affect the existing window for the LPs that already intended to withdraw. 
        @dev   Only the Governor can call this function. 
        @dev   It emits a `GlobalsParamSet` event. 
        @param newLpWithdrawWindow The new value for the withdraw window.
     */
    function setLpWithdrawWindow(uint256 newLpWithdrawWindow) external;

    /**
        @dev   Sets the allowed Uniswap slippage percentage, in basis points. 
        @dev   Only the Governor can call this function. 
        @dev   It emits a `GlobalsParamSet` event. 
        @param newMaxSlippage The new max slippage percentage (in basis points)
     */
    function setMaxSwapSlippage(uint256 newMaxSlippage) external;

    /**
      @dev   Sets the Global Admin. 
      @dev   Only the Governor can call this function. 
      @dev   It emits a `GlobalAdminSet` event. 
      @param newGlobalAdmin The new global admin address.
     */
    function setGlobalAdmin(address newGlobalAdmin) external;

    /**
        @dev   Sets the validity of a Balancer Pool. 
        @dev   Only the Governor can call this function. 
        @dev   It emits a `BalancerPoolSet` event. 
        @param balancerPool The address of Balancer Pool contract.
        @param valid        The new validity status of a Balancer Pool.
     */
    function setValidBalancerPool(address balancerPool, bool valid) external;

    /**
        @dev   Sets the paused/unpaused state of the protocol. 
        @dev   Only the Global Admin can call this function. 
        @dev   It emits a `ProtocolPaused` event. 
        @param pause A boolean flag to switch externally facing functionality in the protocol on/off.
     */
    function setProtocolPause(bool pause) external;

    /**
        @dev   Sets the validity of a PoolFactory. 
        @dev   Only the Governor can call this function. 
        @param poolFactory The address of a PoolFactory.
        @param valid       The new validity status of `poolFactory`.
     */
    function setValidPoolFactory(address poolFactory, bool valid) external;

    /**
        @dev   Sets the validity of a LoanFactory. 
        @dev   Only the Governor can call this function. 
        @param loanFactory The address of a LoanFactory.
        @param valid       The new validity status of `loanFactory`.
     */
    function setValidLoanFactory(address loanFactory, bool valid) external;

    /**
        @dev   Sets the validity of `subFactory` as it relates to `superFactory`. 
        @dev   Only the Governor can call this function. 
        @param superFactory The core factory (e.g. PoolFactory, LoanFactory).
        @param subFactory   The sub factory used by core factory (e.g. LiquidityLockerFactory).
        @param valid        The new validity status of `subFactory` within context of `superFactory`.
     */
    function setValidSubFactory(address superFactory, address subFactory, bool valid) external;

    /**
        @dev   Sets the path to swap an asset through Uniswap. 
        @dev   Only the Governor can call this function. 
        @dev   Set to == mid to enable a bilateral swap (single path swap). 
        @dev   Set to != mid to enable a triangular swap (multi path swap). 
        @param from The address of the asset being swapped.
        @param to   The address of the final asset to receive.
        @param mid  The intermediary asset for swaps, if any.
     */
    function setDefaultUniswapPath(address from, address to, address mid) external;

    /**
        @dev   Sets the validity of a Pool Delegate (those allowed to create Pools). 
        @dev   Only the Governor can call this function. 
        @dev   It emits a `PoolDelegateSet` event. 
        @param poolDelegate The address to manage permissions for.
        @param valid        The new validity status of a Pool Delegate.
     */
    function setPoolDelegateAllowlist(address poolDelegate, bool valid) external;

    /**
        @dev   Sets the validity of an asset for collateral. 
        @dev   Only the Governor can call this function. 
        @dev   It emits a `CollateralAssetSet` event. 
        @param asset The asset to assign validity to.
        @param valid The new validity status of a Collateral Asset.
     */
    function setCollateralAsset(address asset, bool valid) external;

    /**
        @dev   Sets the validity of an asset for liquidity in Pools. 
        @dev   Only the Governor can call this function. 
        @dev   It emits a `LiquidityAssetSet` event. 
        @param asset The asset to assign validity to.
        @param valid The new validity status a Liquidity Asset in Pools.
     */
    function setLiquidityAsset(address asset, bool valid) external;

    /**
        @dev   Sets the validity of a calculator contract. 
        @dev   Only the Governor can call this function. 
        @param calc  The Calculator address.
        @param valid The new validity status of a Calculator.
     */
    function setCalc(address calc, bool valid) external;

    /**
        @dev   Sets the investor fee (in basis points). 
        @dev   Only the Governor can call this function. 
        @dev   It emits a `GlobalsParamSet` event. 
        @param _fee The fee, e.g., 50 = 0.50%.
     */
    function setInvestorFee(uint256 _fee) external;

    /**
        @dev   Sets the treasury fee (in basis points). 
        @dev   Only the Governor can call this function. 
        @dev   It emits a `GlobalsParamSet` event. 
        @param _fee The fee, e.g., 50 = 0.50%.
     */
    function setTreasuryFee(uint256 _fee) external;

    /**
        @dev   Sets the MapleTreasury. 
        @dev   Only the Governor can call this function. 
        @dev   It emits a `GlobalsParamSet` event. 
        @param _mapleTreasury A new MapleTreasury address.
     */
    function setMapleTreasury(address _mapleTreasury) external;

    /**
        @dev   Sets the default grace period. 
        @dev   Only the Governor can call this function. 
        @dev   It emits a `GlobalsParamSet` event. 
        @param _defaultGracePeriod The new number of seconds to set the grace period to.
     */
    function setDefaultGracePeriod(uint256 _defaultGracePeriod) external;

    /**
        @dev   Sets the minimum Loan equity. 
        @dev   Only the Governor can call this function. 
        @dev   It emits a `GlobalsParamSet` event. 
        @param _minLoanEquity The new minimum percentage of Loan equity an account must have to trigger liquidations.
     */
    function setMinLoanEquity(uint256 _minLoanEquity) external;

    /**
        @dev   Sets the funding period. 
        @dev   Only the Governor can call this function. 
        @dev   It emits a `GlobalsParamSet` event. 
        @param _fundingPeriod The number of seconds to set the drawdown grace period to.
     */
    function setFundingPeriod(uint256 _fundingPeriod) external;

    /**
        @dev   Sets the the minimum Pool cover required to finalize a Pool. 
        @dev   Only the Governor can call this function. 
        @dev   It emits a `GlobalsParamSet` event. 
        @param amt The new minimum swap out required.
     */
    function setSwapOutRequired(uint256 amt) external;

    /**
        @dev   Sets a price feed's oracle. 
        @dev   Only the Governor can call this function. 
        @dev   It emits a `OracleSet` event. 
        @param asset  The asset to update price for.
        @param oracle The new Oracle to use for the price of `asset`.
     */
    function setPriceOracle(address asset, address oracle) external;

    /**
        @dev   Sets a new Pending Governor. 
        @dev   This address can become Governor if they accept. 
        @dev   Only the Governor can call this function. 
        @dev   It emits a `PendingGovernorSet` event. 
        @param _pendingGovernor The address of a new Pending Governor.
     */
    function setPendingGovernor(address _pendingGovernor) external;

    /**
        @dev Accept the Governor position. 
        @dev Only the Pending Governor can call this function. 
        @dev It emits a `GovernorAccepted` event. 
     */
    function acceptGovernor() external;

    /**
        @dev    Fetch price for asset from Chainlink oracles.
        @param  asset The asset to fetch the price of.
        @return The price of asset in USD.
     */
    function getLatestPrice(address asset) external view returns (uint256);

    /**
        @dev   Checks that a `subFactory` is valid as it relates to `superFactory`.
        @param superFactory The core factory (e.g. PoolFactory, LoanFactory).
        @param subFactory   The sub factory used by core factory (e.g. LiquidityLockerFactory).
        @param factoryType  The type expected for the subFactory. 
                                0 = COLLATERAL_LOCKER_FACTORY, 
                                1 = DEBT_LOCKER_FACTORY, 
                                2 = FUNDING_LOCKER_FACTORY, 
                                3 = LIQUIDITY_LOCKER_FACTORY, 
                                4 = STAKE_LOCKER_FACTORY. 
     */
    function isValidSubFactory(address superFactory, address subFactory, uint8 factoryType) external view returns (bool);

    /**
        @dev   Checks that a Calculator is valid.
        @param calc     The Calculator address.
        @param calcType The Calculator type.
     */
    function isValidCalc(address calc, uint8 calcType) external view returns (bool);

    /**
        @dev    Returns the `lpCooldownPeriod` and `lpWithdrawWindow` as a tuple, for convenience.
        @return The value of `lpCooldownPeriod`.
        @return The value of `lpWithdrawWindow`.
     */
    function getLpCooldownParams() external view returns (uint256, uint256);

}
