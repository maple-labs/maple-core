// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { IERC20 } from "../../../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { IPoolFDT } from "./IPoolFDT.sol";

/// @title Pool maintains all accounting and functionality related to Pools.
interface IPool is IPoolFDT {

    /**
        Initialized = The Pool has been initialized and is ready for liquidity.
        Finalized   = The Pool has been sufficiently sourced wth liquidity.
        Deactivated = The Pool has been emptied and deactivated.
     */
    enum State { Initialized, Finalized, Deactivated }

    /**
        @dev   Emits an event indicating a Loan was funded.
        @param loan         The funded Loan.
        @param debtLocker   The DebtLocker.
        @param amountFunded The amount the Loan was funded for.
     */
    event LoanFunded(address indexed loan, address debtLocker, uint256 amountFunded);

    /**
        @dev   Emits an event indicating a Loan was claimed.
        @param loan                The Loan.
        @param interest            The interest.
        @param principal           The principal.
        @param fee                 The total fee.
        @param stakeLockerPortion  The portion of the fee for Stakers.
        @param poolDelegatePortion The portion of the fee for the Pool Delegate.
     */
    event Claim(address indexed loan, uint256 interest, uint256 principal, uint256 fee, uint256 stakeLockerPortion, uint256 poolDelegatePortion);

    /**
        @dev   Emits an event indicating some Balance was updated.
        @param liquidityProvider The address of a Liquidity Provider.
        @param token             The address of the token for which the balance of `liquidityProvider` changed.
        @param balance           The new balance for `liquidityProvider`.
     */
    event BalanceUpdated(address indexed liquidityProvider, address indexed token, uint256 balance);

    /**
        @dev   Emits an event indicating a transfer of funds was performed by a custodian.
        @param custodian The address of the custodian.
        @param from      The source of funds that were custodied.
        @param to        The destination of funds.
        @param amount    The amount of custodied tokens transferred.
     */
    event CustodyTransfer(address indexed custodian, address indexed from, address indexed to, uint256 amount);

    /**
        @dev   Emits an event indicating a change in the total amount in custodianship for an account.
        @param liquidityProvider The address of amount who's funds are being custodied.
        @param custodian         The address of the custodian.
        @param oldAllowance      The original total amount in custodian by `custodian` for `liquidityProvider`.
        @param newAllowance      The updated total amount in custodian by `custodian` for `liquidityProvider`.
     */
    event CustodyAllowanceChanged(address indexed liquidityProvider, address indexed custodian, uint256 oldAllowance, uint256 newAllowance);

    /**
        @dev   Emits an event indicating a that a Liquidity Provider's status has changed.
        @param liquidityProvider The address of a Liquidity Provider.
        @param status            The new status of `liquidityProvider`.
     */
    event LPStatusChanged(address indexed liquidityProvider, bool status);

    /**
        @dev   Emits an event indicating a that the Liquidity Cap for the Pool was set.
        @param newLiquidityCap The new liquidity cap.
     */
    event LiquidityCapSet(uint256 newLiquidityCap);

    /**
        @dev   Emits an event indicating a that the lockup period for the Pool was set.
        @param newLockupPeriod The new lockup cap.
     */
    event LockupPeriodSet(uint256 newLockupPeriod);

    /**
        @dev   Emits an event indicating a that the staking fee for the Pool was set.
        @param newStakingFee The new fee Stakers earn (in basis points).
     */
    event StakingFeeSet(uint256 newStakingFee);

    /**
        @dev   Emits an event indicating a that the state of the Pool has changed.
        @param state The new state of the Pool.
     */
    event PoolStateChanged(State state);

    /**
        @dev   Emits an event indicating a that the withdrawal cooldown for a Liquidity Provider of the Pool has updated.
        @param liquidityProvider The address of a Liquidity Provider.
        @param cooldown          The new withdrawal cooldown.
     */
    event Cooldown(address indexed liquidityProvider, uint256 cooldown);

    /**
        @dev   Emits an event indicating a that a Pool's openness to the public has changed.
        @param isOpen Whether the Pool is open to the public to add liquidity.
     */
    event PoolOpenedToPublic(bool isOpen);

    /**
        @dev   Emits an event indicating a that a PoolAdmin was set.
        @param poolAdmin The address of a PoolAdmin.
        @param allowed   Whether `poolAdmin` is an admin of the Pool.
     */
    event PoolAdminSet(address indexed poolAdmin, bool allowed);

    /**
        @dev   Emits an event indicating a that a Liquidity Provider's effective deposit date has changed.
        @param liquidityProvider The address of a Liquidity Provider.
        @param depositDate       The new effective deposit date.
     */
    event DepositDateUpdated(address indexed liquidityProvider, uint256 depositDate);

    /**
        @dev   Emits an event indicating a that a Liquidity Provider's total amount in custody of custodians has changed.
        @param liquidityProvider The address of a Liquidity Provider.
        @param newTotalAllowance The total amount in custody of custodians for `liquidityProvider`.
     */
    event TotalCustodyAllowanceUpdated(address indexed liquidityProvider, uint256 newTotalAllowance);

    /**
        @dev   Emits an event indicating the one of the Pool's Loans defaulted.
        @param loan                            The address of the Loan that defaulted.
        @param defaultSuffered                 The amount of default suffered.
        @param bptsBurned                      The amount of BPTs burned to recover funds.
        @param bptsReturned                    The amount of BPTs returned to Liquidity Provider.
        @param liquidityAssetRecoveredFromBurn The amount of Liquidity Asset recovered from burning BPTs.
     */
    event DefaultSuffered(
        address indexed loan,
        uint256 defaultSuffered,
        uint256 bptsBurned,
        uint256 bptsReturned,
        uint256 liquidityAssetRecoveredFromBurn
    );

    /**
        @dev The factory type of `DebtLockerFactory`.
     */
    function DL_FACTORY() external pure returns (uint8);

    /**
        @dev The asset deposited by Lenders into the LiquidityLocker, for funding Loans.
     */
    function liquidityAsset() external pure returns (IERC20);

    /**
        @dev The Pool Delegate address, maintains full authority over the Pool.
     */
    function poolDelegate() external pure returns (address);

    /**
        @dev The address of the asset deposited by Stakers into the StakeLocker (BPTs), for liquidation during default events.
     */
    function liquidityLocker() external pure returns (address);

    /**
        @dev The address of the asset deposited by Stakers into the StakeLocker (BPTs), for liquidation during default events.
     */
    function stakeAsset() external pure returns (address);

    /**
        @dev The address of the StakeLocker, escrowing `stakeAsset`.
     */
    function stakeLocker() external pure returns (address);

    /**
        @dev The factory that deployed this Loan.
     */
    function superFactory() external pure returns (address);

    /**
        @dev The fee Stakers earn (in basis points).
     */
    function stakingFee() external view returns (uint256);

    /**
        @dev The fee the Pool Delegate earns (in basis points).
     */
    function delegateFee() external pure returns (uint256);

    /**
        @dev The sum of all outstanding principal on Loans.
     */
    function principalOut() external view returns (uint256);

    /**
        @dev The amount of liquidity tokens accepted by the Pool.
     */
    function liquidityCap() external view returns (uint256);

    /**
        @dev The period of time from an account's deposit date during which they cannot withdraw any funds.
     */
    function lockupPeriod() external view returns (uint256);

    /**
        @dev Whether the Pool is open to the public for LP deposits.
     */
    function openToPublic() external view returns (bool);

    /**
        @dev The state of the Pool.
     */
    function poolState() external view returns (State);

    /**
        @dev    Used for withdraw penalty calculation.
        @param  account The address of an account.
        @return The unix timestamp of the weighted average deposit date of `account`.
     */
    function depositDate(address account) external view returns (uint256);

    /**
        @param  loan              The address of a Loan.
        @param  debtLockerFactory The address of a DebtLockerFactory.
        @return The address of the DebtLocker corresponding to `loan` and `debtLockerFactory`.
     */
    function debtLockers(address loan, address debtLockerFactory) external view returns (address);

    /**
        @param  poolAdmin The address of a PoolAdmin.
        @return Whether `poolAdmin` has permission to do certain operations in case of disaster management.
     */
    function poolAdmins(address poolAdmin) external view returns (bool);

    /**
        @param  liquidityProvider The address of a LiquidityProvider.
        @return Whether `liquidityProvider` has early access to the Pool.
     */
    function allowedLiquidityProviders(address liquidityProvider) external view returns (bool);

    /**
        @param  liquidityProvider The address of a LiquidityProvider.
        @return The unix timestamp of when individual LPs have notified of their intent to withdraw.
     */
    function withdrawCooldown(address liquidityProvider) external view returns (uint256);

    /**
        @param  account   The address of an account.
        @param  custodian The address of a custodian.
        @return The amount of PoolFDTs of `account` that are "locked" at `custodian`.
     */
    function custodyAllowance(address account, address custodian) external view returns (uint256);

    /**
        @param  account   The address of an account.
        @return The total amount of PoolFDTs that are "locked" for `account`. Cannot be greater than the account's balance.
     */
    function totalCustodyAllowance(address account) external view returns (uint256);

    /**
        @dev Finalizes the Pool, enabling deposits. 
        @dev Checks the amount the Pool Delegate deposited to the StakeLocker. 
        @dev Only the Pool Delegate can call this function. 
        @dev It emits a `PoolStateChanged` event. 
     */
    function finalize() external;

    /**
        @dev   Funds a Loan for an amount, utilizing the supplied DebtLockerFactory for DebtLockers. 
        @dev   Only the Pool Delegate can call this function. 
        @dev   It emits a `LoanFunded` event. 
        @dev   It emits a `BalanceUpdated` event. 
        @param loan      The address of the Loan to fund.
        @param dlFactory The address of the DebtLockerFactory to utilize.
        @param amt       The amount to fund the Loan.
     */
    function fundLoan(address loan, address dlFactory, uint256 amt) external;

    /**
        @dev   Liquidates a Loan. 
        @dev   The Pool Delegate could liquidate the Loan only when the Loan completes its grace period. 
        @dev   The Pool Delegate can claim its proportion of recovered funds from the liquidation using the `claim()` function. 
        @dev   Only the Pool Delegate can call this function. 
        @param loan      The address of the Loan to liquidate.
        @param dlFactory The address of the DebtLockerFactory that is used to pull corresponding DebtLocker.
     */
    function triggerDefault(address loan, address dlFactory) external;

    /**
        @dev    Claims available funds for the Loan through a specified DebtLockerFactory. 
        @dev    Only the Pool Delegate or a Pool Admin can call this function. 
        @dev    It emits two `BalanceUpdated` events. 
        @dev    It emits a `Claim` event. 
        @param  loan      The address of the loan to claim from.
        @param  dlFactory The address of the DebtLockerFactory.
        @return claimInfo The claim details. 
                    [0] => Total amount claimed, 
                    [1] => Interest portion claimed, 
                    [2] => Principal portion claimed, 
                    [3] => Fee portion claimed, 
                    [4] => Excess portion claimed, 
                    [5] => Recovered portion claimed (from liquidations), 
                    [6] => Default suffered. 
     */
    function claim(address loan, address dlFactory) external returns (uint256[7] memory claimInfo);

    /**
        @dev Triggers deactivation, permanently shutting down the Pool. 
        @dev Must have less than 100 USD worth of Liquidity Asset `principalOut`. 
        @dev Only the Pool Delegate can call this function. 
        @dev It emits a `PoolStateChanged` event. 
     */
    function deactivate() external;
    
    /**
        @dev   Sets the liquidity cap. 
        @dev   Only the Pool Delegate or a Pool Admin can call this function. 
        @dev   It emits a `LiquidityCapSet` event. 
        @param newLiquidityCap The new liquidity cap value.
     */
    function setLiquidityCap(uint256 newLiquidityCap) external;

    /**
        @dev   Sets the lockup period. 
        @dev   Only the Pool Delegate can call this function. 
        @dev   It emits a `LockupPeriodSet` event. 
        @param newLockupPeriod The new lockup period used to restrict the withdrawals.
     */
    function setLockupPeriod(uint256 newLockupPeriod) external;

    /**
        @dev   Sets the staking fee. 
        @dev   Only the Pool Delegate can call this function. 
        @dev   It emits a `StakingFeeSet` event. 
        @param newStakingFee The new staking fee.
     */
    function setStakingFee(uint256 newStakingFee) external;

    /**
        @dev   Sets the account status in the Pool's allowlist. 
        @dev   Only the Pool Delegate can call this function. 
        @dev   It emits an `LPStatusChanged` event. 
        @param account The address to set status for.
        @param status  The status of an account in the allowlist.
     */
    function setAllowList(address account, bool status) external;

    /**
        @dev   Sets a Pool Admin. 
        @dev   Only the Pool Delegate can call this function. 
        @dev   It emits a `PoolAdminSet` event. 
        @param poolAdmin An address being allowed or disallowed as a Pool Admin.
        @param allowed   Whether `poolAdmin` is an admin of the Pool.
     */
    function setPoolAdmin(address poolAdmin, bool allowed) external;

    /**
        @dev   Sets whether the Pool is open to the public. 
        @dev   Only the Pool Delegate can call this function. 
        @dev   It emits a `PoolOpenedToPublic` event. 
        @param open Whether the Pool is open to liquidity from the public.
     */
    function setOpenToPublic(bool open) external;

    /**
        @dev   Handles Liquidity Providers depositing of Liquidity Asset into the LiquidityLocker, minting PoolFDTs. 
        @dev   It emits a `DepositDateUpdated` event. 
        @dev   It emits a `BalanceUpdated` event. 
        @dev   It emits a `Cooldown` event. 
        @param amt The amount of Liquidity Asset to deposit.
     */
    function deposit(uint256 amt) external;

    /**
        @dev Activates the cooldown period to withdraw. 
        @dev It can't be called if the account is not providing liquidity. 
        @dev It emits a `Cooldown` event. 
     */
    function intendToWithdraw() external;

    /**
        @dev Cancels an initiated withdrawal by resetting the account's withdraw cooldown. 
        @dev It emits a `Cooldown` event. 
     */
    function cancelWithdraw() external;

    /**
        @dev   Handles Liquidity Providers withdrawing of Liquidity Asset from the LiquidityLocker, burning PoolFDTs. 
        @dev   It emits two `BalanceUpdated` event. 
        @param amt The amount of Liquidity Asset to withdraw.
     */
    function withdraw(uint256 amt) external;

    /**
        @dev Withdraws all claimable interest from the LiquidityLocker for an account using `interestSum` accounting. 
        @dev It emits a `BalanceUpdated` event. 
     */
    function withdrawFunds() external override;

    /**
        @dev   Increases the custody allowance for a given Custodian corresponding to the calling account (`msg.sender`). 
        @dev   It emits a `CustodyAllowanceChanged` event. 
        @dev   It emits a `TotalCustodyAllowanceUpdated` event. 
        @param custodian The address which will act as Custodian of a given amount for an account.
        @param amount    The number of additional FDTs to be custodied by the Custodian.
     */
    function increaseCustodyAllowance(address custodian, uint256 amount) external;

    /**
        @dev   Transfers custodied PoolFDTs back to the account. 
        @dev   `from` and `to` should always be equal in this implementation. 
        @dev   This means that the Custodian can only decrease their own allowance and unlock funds for the original owner. 
        @dev   It emits a `CustodyTransfer` event. 
        @dev   It emits a `CustodyAllowanceChanged` event. 
        @dev   It emits a `TotalCustodyAllowanceUpdated` event. 
        @param from   The address which holds the PoolFDTs.
        @param to     The address which will be the new owner of the amount of PoolFDTs.
        @param amount The amount of PoolFDTs transferred.
     */
    function transferByCustodian(address from, address to, uint256 amount) external;

    /**
        @dev   Transfers any locked funds to the Governor. 
        @dev   Only the Governor can call this function. 
        @param token The address of the token to be reclaimed.
     */
    function reclaimERC20(address token) external;
    
    /**
        @dev    Calculates the value of BPT in units of Liquidity Asset.
        @param  _bPool          The address of Balancer pool.
        @param  _liquidityAsset The asset used by Pool for liquidity to fund Loans.
        @param  _staker         The address that deposited BPTs to StakeLocker.
        @param  _stakeLocker    Escrows BPTs deposited by Staker.
        @return USDC value of staker BPTs.
     */
    function BPTVal(
        address _bPool,
        address _liquidityAsset,
        address _staker,
        address _stakeLocker
    ) external view returns (uint256);

    /**
        @dev   Checks that the given deposit amount is acceptable based on current liquidityCap.
        @param depositAmt The amount of tokens (i.e liquidityAsset type) the account is trying to deposit.
     */
    function isDepositAllowed(uint256 depositAmt) external view returns (bool);

    /**
        @dev    Returns information on the stake requirements.
        @return The min amount of Liquidity Asset coverage from staking required.
        @return The present amount of Liquidity Asset coverage from the Pool Delegate stake.
        @return Whether enough stake is present from the Pool Delegate for finalization.
        @return The staked BPTs required for minimum Liquidity Asset coverage.
        @return The current staked BPTs.
     */
    function getInitialStakeRequirements() external view returns (uint256, uint256, bool, uint256, uint256);

    /**
        @dev    Calculates BPTs required if burning BPTs for the Liquidity Asset, given supplied `tokenAmountOutRequired`.
        @param  _bPool                        The Balancer pool that issues the BPTs.
        @param  _liquidityAsset               Swap out asset (e.g. USDC) to receive when burning BPTs.
        @param  _staker                       The address that deposited BPTs to StakeLocker.
        @param  _stakeLocker                  Escrows BPTs deposited by Staker.
        @param  _liquidityAssetAmountRequired The amount of Liquidity Asset required to recover.
        @return The `poolAmountIn` required.
        @return The `poolAmountIn` currently staked.
     */
    function getPoolSharesRequired(
        address _bPool,
        address _liquidityAsset,
        address _staker,
        address _stakeLocker,
        uint256 _liquidityAssetAmountRequired
    ) external view returns (uint256, uint256);

    /**
      @dev    Checks that the Pool state is `Finalized`.
      @return Whether the Pool is in a Finalized state.
     */
    function isPoolFinalized() external view returns (bool);

}
