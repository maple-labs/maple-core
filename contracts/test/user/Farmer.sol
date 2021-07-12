// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { IERC20 } from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { MplRewards } from "../../core/mpl-rewards/v1/MplRewards.sol";
import { IERC2258 } from "../../core/custodial-ownership-token/v1/interfaces/IERC2258.sol";
import { IStakeLocker } from "../../core/stake-locker/v1/interfaces/IStakeLocker.sol";

import { LP } from "./LP.sol";

// Farmers & Staker can be used interchangeably so supporting staking functions.
contract Farmer is LP {

    MplRewards public mplRewards;
    IERC20     public stakeToken;

    constructor(MplRewards _mplRewards, IERC20 _stakeToken) public {
        mplRewards = _mplRewards;
        stakeToken = _stakeToken;
    }

    /************************/
    /*** DIRECT FUNCTIONS ***/
    /************************/

    function increaseCustodyAllowance(address dst, uint256 amt) public {
        IERC2258(address(stakeToken)).increaseCustodyAllowance(dst, amt);
    }

    function transfer(address asset, address to, uint256 amt) public {
        IERC20(asset).transfer(to, amt);
    }

    function stake(uint256 amt) public {
        mplRewards.stake(amt);
    }

    function withdraw(uint256 amt) public {
        mplRewards.withdraw(amt);
    }

    function getReward() public {
        mplRewards.getReward();
    }

    function exit() public {
        mplRewards.exit();
    }

    function stakeTo(address stakeLocker, uint256 amt) public {
        IStakeLocker(stakeLocker).stake(amt);
    }

    /*********************/
    /*** TRY FUNCTIONS ***/
    /*********************/

    function try_stake(uint256 amt) external returns (bool ok) {
        string memory sig = "stake(uint256)";
        (ok,) = address(mplRewards).call(abi.encodeWithSignature(sig, amt));
    }

    function try_withdraw(uint256 amt) external returns (bool ok) {
        string memory sig = "withdraw(uint256)";
        (ok,) = address(mplRewards).call(abi.encodeWithSignature(sig, amt));
    }

    function try_increaseCustodyAllowance(address account, uint256 amt) external returns (bool ok) {
        string memory sig = "increaseCustodyAllowance(address,uint256)";
        (ok,) = address(stakeToken).call(abi.encodeWithSignature(sig, account, amt));
    }

    function try_stakeTo(address stakeLocker, uint256 amt) external returns (bool ok) {
        string memory sig = "stake(uint256)";
        (ok,) = address(stakeLocker).call(abi.encodeWithSignature(sig, amt));
    }

    function try_unstake(address stakeLocker, uint256 amt) external returns (bool ok) {
        string memory sig = "unstake(uint256)";
        (ok,) = address(stakeLocker).call(abi.encodeWithSignature(sig, amt));
    }

    function try_intendToUnstake(address stakeLocker) external returns (bool ok) {
        string memory sig = "intendToUnstake()";
        (ok,) = stakeLocker.call(abi.encodeWithSignature(sig));
    }

}
