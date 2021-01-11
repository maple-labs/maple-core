

## Functions:
[`constructor(address _governor, address _mpl)`](#MapleGlobals-constructor-address-address-)
[`getValidTokens()`](#MapleGlobals-getValidTokens--)
[`setPoolFactory(address _poolFactory)`](#MapleGlobals-setPoolFactory-address-)
[`setLoanFactory(address _loanFactory)`](#MapleGlobals-setLoanFactory-address-)
[`setMapleBPool(address _mapleBPool)`](#MapleGlobals-setMapleBPool-address-)
[`setPoolDelegateWhitelist(address delegate, bool valid)`](#MapleGlobals-setPoolDelegateWhitelist-address-bool-)
[`setMapleBPoolAssetPair(address asset)`](#MapleGlobals-setMapleBPoolAssetPair-address-)
[`assignPriceFeed(address asset, address oracle)`](#MapleGlobals-assignPriceFeed-address-address-)
[`getPrice(address asset)`](#MapleGlobals-getPrice-address-)
[`setCollateralAsset(address asset, bool valid)`](#MapleGlobals-setCollateralAsset-address-bool-)
[`setLoanAsset(address asset, bool valid)`](#MapleGlobals-setLoanAsset-address-bool-)
[`setCalc(address calc, bool valid)`](#MapleGlobals-setCalc-address-bool-)
[`setInvestorFee(uint256 _fee)`](#MapleGlobals-setInvestorFee-uint256-)
[`setTreasuryFee(uint256 _fee)`](#MapleGlobals-setTreasuryFee-uint256-)
[`setMapleTreasury(address _mapleTreasury)`](#MapleGlobals-setMapleTreasury-address-)
[`setGracePeriod(uint256 _gracePeriod)`](#MapleGlobals-setGracePeriod-uint256-)
[`setStakeRequired(uint256 amtRequired)`](#MapleGlobals-setStakeRequired-uint256-)
[`setGovernor(address _newGovernor)`](#MapleGlobals-setGovernor-address-)
[`setUnstakeDelay(uint256 _unstakeDelay)`](#MapleGlobals-setUnstakeDelay-uint256-)

## Events:
[`CollateralAssetSet(address asset, uint256 decimals, bool valid)`](#MapleGlobals-CollateralAssetSet-address-uint256-bool-)
[`LoanAssetSet(address asset, uint256 decimals, bool valid)`](#MapleGlobals-LoanAssetSet-address-uint256-bool-)

## <u>Functions</u>

### `constructor(address _governor, address _mpl)`
Constructor function.
        @dev    Initializes the contract's state variables.
        @param  _governor The administrator's address.
        @param  _mpl The address of the ERC-2222 token for the Maple protocol.

### `getValidTokens()`
Returns information on valid collateral and loan assets (for Pools and Loans).
        @return [0] = Valid loan asset symbols.
                [1] = Valid loan asset (addresses).
                [2] = Valid collateral asset symbols.
                [3] = Valid collateral asset (addresses).

### `setPoolFactory(address _poolFactory)`
Set the poolFactory to a new factory.
        @param  _poolFactory The new value to assign to poolFactory.

### `setLoanFactory(address _loanFactory)`
Set the loanFactory to a new factory.
        @param  _loanFactory The new value to assign to loanFactory.

### `setMapleBPool(address _mapleBPool)`
Set the mapleBPool to a new balancer pool.
        @param  _mapleBPool The new value to assign to mapleBPool.

### `setPoolDelegateWhitelist(address delegate, bool valid)`
Update validity of pool delegate (those able to create pools).
        @param  delegate The address to manage permissions for.
        @param  valid    The new permissions of delegate.

### `setMapleBPoolAssetPair(address asset)`
Update the mapleBPoolAssetPair (initially planned to be USDC).
        @param  asset The address to manage permissions / validity for.

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

### `setStakeRequired(uint256 amtRequired)`
Governor can adjust the stake amount required to create a pool.
        @param amtRequired The new minimum stake required.

### `setGovernor(address _newGovernor)`
Governor can specify a new governor.
        @param _newGovernor The address of new governor.

### `setUnstakeDelay(uint256 _unstakeDelay)`
Governor can specify a new unstake delay value.
        @param _unstakeDelay The new unstake delay.

## <u>Events</u>

### `CollateralAssetSet(address asset, uint256 decimals, bool valid)`
No description

### `LoanAssetSet(address asset, uint256 decimals, bool valid)`
No description
