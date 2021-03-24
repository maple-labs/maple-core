// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "../../interfaces/IPool.sol";
import "../../interfaces/IPoolFactory.sol";
import "../../interfaces/IStakeLocker.sol";

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

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

    function approve(address token, address who, uint256 amt) external {
        IERC20(token).approve(who, amt);
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

    function claim(address pool, address loan, address dlFactory) external returns(uint256[7] memory) {
        return IPool(pool).claim(loan, dlFactory);  
    }

    function deactivate(address pool, uint confirmation) external {
        IPool(pool).deactivate(confirmation);
    }

    function setPrincipalPenalty(address pool, uint256 penalty) external {
        IPool(pool).setPrincipalPenalty(penalty);
    }

    function setPenaltyDelay(address pool, uint256 delay) external {
        IPool(pool).setPenaltyDelay(delay);
    }

    function setAllowlistStakeLocker(address pool, address user, bool status) external {
        IPool(pool).setAllowlistStakeLocker(user, status);
    }

    function triggerDefault(address pool, address loan, address dlFactory) external {
        IPool(pool).triggerDefault(loan, dlFactory);
    }
    
    function setAdmin(address pool, address newAdmin, bool status) external {
        IPool(pool).setAdmin(newAdmin, status);
    }

    function openPoolToPublic(address pool) external {
        IPool(pool).openPoolToPublic();
    }

    function openStakeLockerToPublic(address stakeLocker) external {
        IStakeLocker(stakeLocker).openStakeLockerToPublic();
    }

    function setAllowList(address pool, address user, bool status) external {
        IPool(pool).setAllowList(user, status);
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

    function try_claim(address pool, address loan, address dlFactory) external returns (bool ok) {
        string memory sig = "claim(address,address)";
        (ok,) = address(pool).call(abi.encodeWithSignature(sig, loan, dlFactory));
    }

    function try_finalize(address pool) external returns (bool ok) {
        string memory sig = "finalize()";
        (ok,) = address(pool).call(abi.encodeWithSignature(sig));
    }

    function try_setPrincipalPenalty(address pool, uint256 penalty) external returns (bool ok) {
        string memory sig = "setPrincipalPenalty(uint256)";
        (ok,) = address(pool).call(abi.encodeWithSignature(sig, penalty));
    }

    function try_setPenaltyDelay(address pool, uint256 delay) external returns (bool ok) {
        string memory sig = "setPenaltyDelay(uint256)";
        (ok,) = address(pool).call(abi.encodeWithSignature(sig, delay));
    }

    function try_deactivate(address pool, uint confirmation) external returns(bool ok) {
        string memory sig = "deactivate(uint256)";
        (ok,) = address(pool).call(abi.encodeWithSignature(sig, confirmation));
    }

    function try_setLiquidityCap(address pool, uint256 liquidityCap) external returns(bool ok) {
        string memory sig = "setLiquidityCap(uint256)";
        (ok,) = address(pool).call(abi.encodeWithSignature(sig, liquidityCap));
    }

    function try_setLockupPeriod(address pool, uint256 newPeriod) external returns(bool ok) {
        string memory sig = "setLockupPeriod(uint256)";
        (ok,) = address(pool).call(abi.encodeWithSignature(sig, newPeriod));
    }

    function try_triggerDefault(address pool, address loan, address dlFactory) external returns(bool ok) {
        string memory sig = "triggerDefault(address,address)";
        (ok,) = address(pool).call(abi.encodeWithSignature(sig, loan, dlFactory));
    }

    function try_openPoolToPublic(address pool) external returns(bool ok) {
        string memory sig = "openPoolToPublic()";
        (ok,) = address(pool).call(abi.encodeWithSignature(sig));
    }

    function try_openStakeLockerToPublic(address stakeLocker) external returns(bool ok) {
        string memory sig = "openStakeLockerToPublic()";
        (ok,) = address(stakeLocker).call(abi.encodeWithSignature(sig));
    }

    function try_setAllowList(address pool, address user, bool status) external returns(bool ok) {
        string memory sig = "setAllowList(address,bool)";
        (ok,) = address(pool).call(abi.encodeWithSignature(sig, user, status));
    }

    function try_setAllowlistStakeLocker(address pool, address user, bool status) external returns(bool ok) {
        string memory sig = "setAllowlistStakeLocker(address,bool)";
        (ok,) = address(pool).call(abi.encodeWithSignature(sig, user, status));
    }

    function try_setAdmin(address pool, address newAdmin, bool status) external returns(bool ok) {
        string memory sig = "setAdmin(address,bool)";
        (ok,) = address(pool).call(abi.encodeWithSignature(sig, newAdmin, status));
    }

    function try_pause(address target) external returns(bool ok) {
        string memory sig = "pause()";
        (ok,) = target.call(abi.encodeWithSignature(sig));
    }

    function try_unpause(address target) external returns(bool ok) {
        string memory sig = "unpause()";
        (ok,) = target.call(abi.encodeWithSignature(sig));
    }
}
