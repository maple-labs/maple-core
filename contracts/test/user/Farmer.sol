// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

import "./LP.sol";

import "../../MplRewards.sol";

contract Farmer is LP {

    MplRewards public mplRewards;
    IERC20     public poolFDT;

    constructor(MplRewards _mplRewards, IERC20 _liquidityAsset) public {
        mplRewards = _mplRewards;
        poolFDT    = _liquidityAsset;
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
}
