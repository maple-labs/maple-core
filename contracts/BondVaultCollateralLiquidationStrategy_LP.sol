// SPDX-License-Identifier: MIT

pragma solidity 0.7.3;

/// @title This contract is responsible for liquidating the collateral of a BondVault to resupply a LiquidityPool.
contract BondVaultCollateralLiquidationStrategy_LP {
    /// @return BondVault from which collateral is liquidated.
    address public BondVault;

    /// @return PoolDelegate of the LiquidityPool.
    address public PoolDelegate;

    /// @return Address of the (ERC-20) CollateralAsset.
    address public CollateralAsset;

    /// @return Address of the (ERC-20) InvestmentAsset the (ERC-20) CollateralAsset is exchanged for.
    address public InvestmentAsset;

    modifier isPoolDelegate() {
        require(msg.sender == PoolDelegate);
        _;
    }

    /// @dev Constructor for BondVaultCollateralLiquidationStrategy_LP.sol
    /// @param _bondVault BondVault from which collateral is liquidated.
    /// @param _poolDelegate PoolDelegate of the liquidity pool.
    /// @param _collateralAsset Address of the (ERC-20) CollateralAsset.
    /// @param _investmentAsset Address of the (ERC-20) InvestmentAsset the (ERC-20) CollateralAsset is exchanged for.
    constructor(
        address _bondVault,
        address _poolDelegate,
        address _collateralAsset,
        address _investmentAsset
    ) {
        BondVault = _bondVault;
        PoolDelegate = _poolDelegate;
        CollateralAsset = _collateralAsset;
        InvestmentAsset = _investmentAsset;
    }

    /// @dev Initiate liquidation of BondVault collateral.
    /// @param _bondVault BondVault from which collateral is liquidated.
    /// @return bool, Represents whether or not liquidation initiation was successful.
    function initiateLiquidation(address _bondVault) external pure returns (bool) {
        return true;
    }

    /// @dev Finalise liquidation of BondVault collateral.
    /// @param _bondVault BondVault from which collateral is liquidated.
    /// @param _investmentAssetWaived Amount (10 ** decimals) of InvestmentAsset stakers will not cover.
    /// @return uint, Amount (10 ** decimals) of InvestmentAsset returned to liquidity pool InvestmentAsset locker.
    function finaliseLiquidation(
        address _bondVault,
        uint256 _investmentAssetWaived
    ) external returns (uint256) {
        return _investmentAssetWaived;
    }

    /// @dev PoolDelegate override/manual withdrawal from this locker.
    /// @param _assetAmount Amount (10 ** decimals) of InvestmentAsset to withdraw from this locker.
    /// @return uint, Amount (10 ** decimals) of InvestmentAsset returned to the PoolDelegate.
    function withdrawFromLocker(uint256 _assetAmount)
        external
        isPoolDelegate
        returns (uint256)
    {
        return _assetAmount;
    }
}

/// @title Factory contract responsible for deploying lockers which handle liquidation of collateral held within a BondVault.
contract BondVaultCollateralLiquidationStrategyFactory_LP {
    /// @return Lockers mapping, index is incremented upon each newLocker() call.
    mapping(uint256 => address) public lockers;

    /// @return Incrementor for number of lockers created.
    uint256 public lockersCreated;

    /// @dev Returns the address of a newLocker when created.
    /// @param _locker Address of the instantiated locker.
    /// @param _poolDelegate (Indexed) PoolDelegate instantiating the locker.
    /// @param _bondVault (Indexed) BondVault from which collateral is liquidated.
    /// @param _collateralAsset Address of the (ERC-20) CollateralAsset.
    /// @param _investmentAsset Address of the (ERC-20) InvestmentAsset the CollateralAsset is exchanged for.
    event NewLocker(
        address _locker,
        address indexed _bondVault,
        address indexed _poolDelegate,
        address _collateralAsset,
        address _investmentAsset
    );

    constructor() public {}

    /// @dev Instantiates a new locker.
    /// @param _poolDelegate PoolDelegate instantiating the locker.
    /// @param _bondVault BondVault from which collateral is liquidated.
    /// @param _collateralAsset Address of the (ERC-20) CollateralAsset.
    /// @param _investmentAsset Address of the (ERC-20) InvestmentAsset the CollateralAsset is exchanged for.
    function newLocker(
        address _bondVault,
        address _poolDelegate,
        address _collateralAsset,
        address _investmentAsset
    ) public returns (address) {
        address _locker = address(
            new BondVaultCollateralLiquidationStrategy_LP(
                _bondVault,
                _poolDelegate,
                _collateralAsset,
                _investmentAsset
            )
        );
        lockers[lockersCreated] = _locker;
        lockersCreated++;
        emit NewLocker(
            _locker,
            _bondVault,
            _poolDelegate,
            _collateralAsset,
            _investmentAsset
        );
        return address(_locker);
    }
}
