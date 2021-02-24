// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "./LP.sol";

import "../../StakingRewards.sol";

contract Farmer is LP {

    StakingRewards public stakingRewards;
    IERC20         public poolFDT;

    constructor(StakingRewards _stakingRewards, IERC20 _liquidityAsset) public {
        stakingRewards = _stakingRewards;
        poolFDT        = _liquidityAsset;
    }

    /************************/
    /*** DIRECT FUNCTIONS ***/
    /************************/

    function approve(address who, uint256 amt) public {
        poolFDT.approve(who, amt);
    }

    function transfer(address asset, address to, uint256 amt) public {
        IERC20(asset).transfer(to, amt);
    }

    function stake(uint256 amt) public {
        stakingRewards.stake(amt);
    }

    function withdraw(uint256 amt) public {
        stakingRewards.withdraw(amt);
    }

    function getReward() public {
        stakingRewards.getReward();
    }

    function exit() public {
        stakingRewards.exit();
    }

    /*********************/
    /*** TRY FUNCTIONS ***/
    /*********************/

    function try_stake(uint256 amt) external returns (bool ok) {
        string memory sig = "stake(uint256)";
        (ok,) = address(stakingRewards).call(abi.encodeWithSignature(sig, amt));
    }

    function try_withdraw(uint256 amt) external returns (bool ok) {
        string memory sig = "withdraw(uint256)";
        (ok,) = address(stakingRewards).call(abi.encodeWithSignature(sig, amt));
    }
}
