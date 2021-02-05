

## Functions:
[`constructor(address _governor, address _mpl, address _bFactory)`](#MapleGlobals-constructor-address-address-address-)
[`setExtendedGracePeriod(uint256 newExtendedGracePeriod)`](#MapleGlobals-setExtendedGracePeriod-uint256-)
[`setValidPoolFactory(address poolFactory, bool valid)`](#MapleGlobals-setValidPoolFactory-address-bool-)
[`setValidLoanFactory(address loanFactory, bool valid)`](#MapleGlobals-setValidLoanFactory-address-bool-)
[`setValidSubFactory(address superFactory, address subFactory, bool valid)`](#MapleGlobals-setValidSubFactory-address-address-bool-)
[`setDefaultUniswapPath(address from, address to, address mid)`](#MapleGlobals-setDefaultUniswapPath-address-address-address-)
[`isValidSubFactory(address superFactory, address subFactory, uint8 factoryType)`](#MapleGlobals-isValidSubFactory-address-address-uint8-)
[`isValidCalc(address calc, uint8 calcType)`](#MapleGlobals-isValidCalc-address-uint8-)
[`setPoolDelegateWhitelist(address delegate, bool valid)`](#MapleGlobals-setPoolDelegateWhitelist-address-bool-)
[`assignPriceFeed(address asset, address oracle)`](#MapleGlobals-assignPriceFeed-address-address-)
[`getPrice(address asset)`](#MapleGlobals-getPrice-address-)
[`setCollateralAsset(address asset, bool valid)`](#MapleGlobals-setCollateralAsset-address-bool-)
[`setLoanAsset(address asset, bool valid)`](#MapleGlobals-setLoanAsset-address-bool-)
[`setCalc(address calc, bool valid)`](#MapleGlobals-setCalc-address-bool-)
[`setInvestorFee(uint256 _fee)`](#MapleGlobals-setInvestorFee-uint256-)
[`setTreasuryFee(uint256 _fee)`](#MapleGlobals-setTreasuryFee-uint256-)
[`setMapleTreasury(address _mapleTreasury)`](#MapleGlobals-setMapleTreasury-address-)
[`setGracePeriod(uint256 _gracePeriod)`](#MapleGlobals-setGracePeriod-uint256-)
[`setDrawdownGracePeriod(uint256 _drawdownGracePeriod)`](#MapleGlobals-setDrawdownGracePeriod-uint256-)
[`setSwapOutRequired(uint256 amt)`](#MapleGlobals-setSwapOutRequired-uint256-)
[`setGovernor(address _newGovernor)`](#MapleGlobals-setGovernor-address-)
[`setUnstakeDelay(uint256 _unstakeDelay)`](#MapleGlobals-setUnstakeDelay-uint256-)
[`getLatestPrice(address asset)`](#MapleGlobals-getLatestPrice-address-)
[`setPriceOracle(address asset, address oracle)`](#MapleGlobals-setPriceOracle-address-address-)

## Events:
[`CollateralAssetSet(address asset, uint256 decimals, string symbol, bool valid)`](#MapleGlobals-CollateralAssetSet-address-uint256-string-bool-)
[`LoanAssetSet(address asset, uint256 decimals, string symbol, bool valid)`](#MapleGlobals-LoanAssetSet-address-uint256-string-bool-)
[`PriceFeedAssigned(address asset, address oracle)`](#MapleGlobals-PriceFeedAssigned-address-address-)

## <u>Functions</u>

### `constructor(address _governor, address _mpl, address _bFactory)`
   Constructor function.
        @param  _governor The administrator's address.
        @param  _mpl      The address of the ERC-2222 token for the Maple protocol.
        @param  _bFactory The official Balancer pool factory.

### `setExtendedGracePeriod(uint256 newExtendedGracePeriod)`
  Update the `extendedGracePeriod` variable.
        @param newExtendedGracePeriod New value of extendedGracePeriod.

### `setValidPoolFactory(address poolFactory, bool valid)`
  Update the valid pool factories mapping.
        @param poolFactory Address of loan factory.
        @param valid       The new bool value for validating poolFactory.

### `setValidLoanFactory(address loanFactory, bool valid)`
  Update the valid loan factories mapping.
        @param loanFactory Address of loan factory.
        @param valid       The new bool value for validating loanFactory.

### `setValidSubFactory(address superFactory, address subFactory, bool valid)`
   Set the validity of a subFactory as it relates to a superFactory.
        @param  superFactory The core factory (e.g. PoolFactory, LoanFactory)
        @param  subFactory   The sub factory used by core factory (e.g. LiquidityLockerFactory)
        @param  valid        The validity of subFactory within context of superFactory.

### `setDefaultUniswapPath(address from, address to, address mid)`
   Set the path to swap an asset through Uniswap.
        @param  from The asset being swapped.
        @param  to   The final asset to receive.*
        @param  mid  The middle path. 
        
Set to == mid to enable a bilateral swap (single path swap).
          Set to != mid to enable a triangular swap (multi path swap).

### `isValidSubFactory(address superFactory, address subFactory, uint8 factoryType)`
   Check the validity of a subFactory as it relates to a superFactory.
        @param  superFactory The core factory (e.g. PoolFactory, LoanFactory)
        @param  subFactory   The sub factory used by core factory (e.g. LiquidityLockerFactory)
        @param  factoryType  The type expected for the subFactory.

### `isValidCalc(address calc, uint8 calcType)`
   Check the validity of a calculator.
        @param  calc The calculator address
        @param  calcType  The calculator type

### `setPoolDelegateWhitelist(address delegate, bool valid)`
Update validity of pool delegate (those able to create pools).
        @param  delegate The address to manage permissions for.
        @param  valid    The new permissions of delegate.

### `assignPriceFeed(address asset, address oracle)`
Update a price feed's oracle.
        @param  asset  The asset to update price for.
        @param  oracle The new oracle to use.

### `getPrice(address asset)`
Get a price feed.
        @param  asset  The asset to fetch price for.

### `setCollateralAsset(address asset, bool valid)`
Set the validity of an asset for collateral.
        @param asset The asset to assign validity to.
        @param valid The new validity of asset as collateral.

### `setLoanAsset(address asset, bool valid)`
Governor can add a valid asset, used for borrowing.
        @param asset Address of the valid asset.
        @param valid Boolean

### `setCalc(address calc, bool valid)`
Specifiy validity of a calculator contract.
        @param  calc  The calculator.
        @param  valid The validity of calc.

### `setInvestorFee(uint256 _fee)`
Governor can adjust investorFee (in basis points).
        @param _fee The fee, 50 = 0.50%

### `setTreasuryFee(uint256 _fee)`
Governor can adjust treasuryFee (in basis points).
        @param _fee The fee, 50 = 0.50%

### `setMapleTreasury(address _mapleTreasury)`
Governor can set the MapleTreasury contract.
        @param _mapleTreasury The MapleTreasury contract.

### `setGracePeriod(uint256 _gracePeriod)`
Governor can adjust the grace period.
        @param _gracePeriod Number of seconds to set the grace period to.

### `setDrawdownGracePeriod(uint256 _drawdownGracePeriod)`
Governor can adjust the drawdown grace period.
        @param _drawdownGracePeriod Number of seconds to set the drawdown grace period to.

### `setSwapOutRequired(uint256 amt)`
Governor can adjust the swap out amount required to finalize a pool.
        @param amt The new minimum swap out required.

### `setGovernor(address _newGovernor)`
Governor can specify a new governor.
        @param _newGovernor The address of new governor.

### `setUnstakeDelay(uint256 _unstakeDelay)`
Governor can specify a new unstake delay value.
        @param _unstakeDelay The new unstake delay.

### `getLatestPrice(address asset)`
Fetch price for asset from ChainLink oracles.
        @param asset The asset to fetch price.
        @return The price of asset.

### `setPriceOracle(address asset, address oracle)`
Governor can specify a new unstake delay value.
        @param asset The new unstake delay.
        @param oracle The new unstake delay.

## <u>Events</u>

### `CollateralAssetSet(address asset, uint256 decimals, string symbol, bool valid)`
No description

### `LoanAssetSet(address asset, uint256 decimals, string symbol, bool valid)`
No description

### `PriceFeedAssigned(address asset, address oracle)`
No description
