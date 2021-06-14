// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "core/mpl-rewards/v1/MplRewards.sol";
import "core/pool/v1/interfaces/IPool.sol";

import "./LP.sol";

contract Farmer is LP {

    MplRewards public mplRewards;
    IERC20     public poolFDT;

    constructor(MplRewards _mplRewards, IERC20 _poolFDT) public {
        mplRewards = _mplRewards;
        poolFDT    = _poolFDT;
    }

    /************************/
    /*** DIRECT FUNCTIONS ***/
    /************************/

    function approve(address account, uint256 amt) public {
        poolFDT.approve(account, amt);
    }

    function increaseCustodyAllowance(address pool, address account, uint256 amt) public {
        IPool(pool).increaseCustodyAllowance(account, amt);
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

    function try_increaseCustodyAllowance(address pool, address account, uint256 amt) external returns (bool ok) {
        string memory sig = "increaseCustodyAllowance(address,uint256)";
        (ok,) = pool.call(abi.encodeWithSignature(sig, account, amt));
    }
}
