// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { IBPool } from "external-interfaces/IBPool.sol";

import { ILoan } from "core/loan/v1/interfaces/ILoan.sol";
import { IPool } from "core/pool/v1/interfaces/IPool.sol";
import { IPoolFactory } from "core/pool/v1/interfaces/IPoolFactory.sol";
import { IStakeLocker } from "core/stake-locker/v1/interfaces/IStakeLocker.sol";

contract PoolDelegate {

    /************************/
    /*** DIRECT FUNCTIONS ***/
    /************************/

    function createPool(
        address poolFactory,
        address liquidityAsset,
        address stakeAsset,
        address slFactory,
        address llFactory,
        uint256 stakingFee,
        uint256 delegateFee,
        uint256 liquidityCap
    )
        external returns (address liquidityPool)
    {
        liquidityPool = IPoolFactory(poolFactory).createPool(
            liquidityAsset,
            stakeAsset,
            slFactory,
            llFactory,
            stakingFee,
            delegateFee,
            liquidityCap
        );
    }

    function approve(address token, address account, uint256 amt) external {
        IERC20(token).approve(account, amt);
    }

    function stake(address stakeLocker, uint256 amt) external {
        IStakeLocker(stakeLocker).stake(amt);
    }

    function finalize(address pool) external {
        IPool(pool).finalize();
    }

    function unstake(address stakeLocker, uint256 amt) external {
        IStakeLocker(stakeLocker).unstake(amt);
    }

    function fundLoan(address pool, address loan, address dlFactory, uint256 amt) external {
        IPool(pool).fundLoan(loan, dlFactory, amt);
    }

    function unwind(address loan) external {
        ILoan(loan).unwind();
    }

    function claim(address pool, address loan, address dlFactory) external returns (uint256[7] memory) {
        return IPool(pool).claim(loan, dlFactory);
    }

    function deactivate(address pool) external {
        IPool(pool).deactivate();
    }

    function triggerDefault(address pool, address loan, address dlFactory) external {
        IPool(pool).triggerDefault(loan, dlFactory);
    }

    function setPoolAdmin(address pool, address newPoolAdmin, bool status) external {
        IPool(pool).setPoolAdmin(newPoolAdmin, status);
    }

    function setOpenToPublic(address pool, bool open) external {
        IPool(pool).setOpenToPublic(open);
    }

    function setLockupPeriod(address pool, uint256 lockupPeriod) external {
        IPool(pool).setLockupPeriod(lockupPeriod);
    }

    function setStakeLockerLockupPeriod(address stakeLocker, uint256 lockupPeriod) external {
        IStakeLocker(stakeLocker).setLockupPeriod(lockupPeriod);
    }

    function setStakingFee(address pool, uint256 stakingFee) external {
        IPool(pool).setStakingFee(stakingFee);
    }

    function setAllowList(address pool, address account, bool status) external {
        IPool(pool).setAllowList(account, status);
    }

    function openStakeLockerToPublic(address stakeLocker) external {
        IStakeLocker(stakeLocker).openStakeLockerToPublic();
    }

    function setAllowlist(address stakeLocker, address account, bool status) external {
        IStakeLocker(stakeLocker).setAllowlist(account, status);
    }

    // Balancer Pool
    function joinBPool(IBPool bPool, uint poolAmountOut, uint[] calldata maxAmountsIn) external {
        bPool.joinPool(poolAmountOut, maxAmountsIn);
    }

    /*********************/
    /*** TRY FUNCTIONS ***/
    /*********************/

    function try_createPool(
        address poolFactory,
        address liquidityAsset,
        address stakeAsset,
        address slFactory,
        address llFactory,
        uint256 stakingFee,
        uint256 delegateFee,
        uint256 liquidityCap
    )
        external returns (bool ok)
    {
        string memory sig = "createPool(address,address,address,address,uint256,uint256,uint256)";
        (ok,) = address(poolFactory).call(
            abi.encodeWithSignature(sig, liquidityAsset, stakeAsset, slFactory, llFactory, stakingFee, delegateFee, liquidityCap)
        );
    }

    function try_fundLoan(address pool, address loan, address dlFactory, uint256 amt) external returns (bool ok) {
        string memory sig = "fundLoan(address,address,uint256)";
        (ok,) = address(pool).call(abi.encodeWithSignature(sig, loan, dlFactory, amt));
    }

    function try_unwind(address loan) external returns (bool ok) {
        string memory sig = "unwind()";
        (ok,) = address(loan).call(abi.encodeWithSignature(sig));
    }

    function try_claim(address pool, address loan, address dlFactory) external returns (bool ok) {
        string memory sig = "claim(address,address)";
        (ok,) = address(pool).call(abi.encodeWithSignature(sig, loan, dlFactory));
    }

    function try_finalize(address pool) external returns (bool ok) {
        string memory sig = "finalize()";
        (ok,) = address(pool).call(abi.encodeWithSignature(sig));
    }

    function try_deactivate(address pool) external returns (bool ok) {
        string memory sig = "deactivate()";
        (ok,) = address(pool).call(abi.encodeWithSignature(sig));
    }

    function try_setLiquidityCap(address pool, uint256 liquidityCap) external returns (bool ok) {
        string memory sig = "setLiquidityCap(uint256)";
        (ok,) = address(pool).call(abi.encodeWithSignature(sig, liquidityCap));
    }

    function try_setLockupPeriod(address pool, uint256 newPeriod) external returns (bool ok) {
        string memory sig = "setLockupPeriod(uint256)";
        (ok,) = address(pool).call(abi.encodeWithSignature(sig, newPeriod));
    }

    function try_setStakingFee(address pool, uint256 newStakingFee) external returns (bool ok) {
        string memory sig = "setStakingFee(uint256)";
        (ok,) = address(pool).call(abi.encodeWithSignature(sig, newStakingFee));
    }

    function try_triggerDefault(address pool, address loan, address dlFactory) external returns (bool ok) {
        string memory sig = "triggerDefault(address,address)";
        (ok,) = address(pool).call(abi.encodeWithSignature(sig, loan, dlFactory));
    }

    function try_setOpenToPublic(address pool, bool open) external returns (bool ok) {
        string memory sig = "setOpenToPublic(bool)";
        (ok,) = address(pool).call(abi.encodeWithSignature(sig, open));
    }

    function try_openStakeLockerToPublic(address stakeLocker) external returns (bool ok) {
        string memory sig = "openStakeLockerToPublic()";
        (ok,) = address(stakeLocker).call(abi.encodeWithSignature(sig));
    }

    function try_setAllowList(address pool, address account, bool status) external returns (bool ok) {
        string memory sig = "setAllowList(address,bool)";
        (ok,) = address(pool).call(abi.encodeWithSignature(sig, account, status));
    }

    function try_setAllowlist(address stakeLocker, address account, bool status) external returns (bool ok) {
        string memory sig = "setAllowlist(address,bool)";
        (ok,) = address(stakeLocker).call(abi.encodeWithSignature(sig, account, status));
    }

    function try_setPoolAdmin(address pool, address newPoolAdmin, bool status) external returns (bool ok) {
        string memory sig = "setPoolAdmin(address,bool)";
        (ok,) = address(pool).call(abi.encodeWithSignature(sig, newPoolAdmin, status));
    }

    function try_pause(address target) external returns (bool ok) {
        string memory sig = "pause()";
        (ok,) = target.call(abi.encodeWithSignature(sig));
    }

    function try_unpause(address target) external returns (bool ok) {
        string memory sig = "unpause()";
        (ok,) = target.call(abi.encodeWithSignature(sig));
    }
}
