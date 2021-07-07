// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./helper/Rewards.sol";

contract StakeLockerCustodialTest is CustodialTestHelper {

    using SafeMath for uint256;

    function setUp() public {
        setupFarmingEcosystem();
        setUpMplRewards(address(stakeLocker1));
        createFarmers();
        addBPoolInTokenSlots();

    }

    function test_custody_and_transfer(uint256 stakeAmt, uint256 custodyAmt1, uint256 custodyAmt2) public {
        custody_and_transfer(stakeAmt, custodyAmt1, custodyAmt2, false, IStakeToken(address(stakeLocker1)));
    }

    function test_custody_and_unstake(uint256 stakeAmt, uint256 custodyAmt) public {
        custody_and_withdraw(stakeAmt, custodyAmt, false, IStakeToken(address(stakeLocker1)));
    }

    function test_transferByCustodian(uint256 stakeAmt, uint256 custodyAmt) public {
        fdt_transferByCustodian(stakeAmt, custodyAmt, false, IStakeToken(address(stakeLocker1)));
    }

    function test_stake() public {
        mint("BPT", address(sam), 1000 * WAD);
        stake_test(false, 1000, 100, IStakeToken(address(stakeLocker1)));
    }

    function test_withdraw() public {
        mint("BPT", address(sam), 1000 * WAD);
        withdraw_test(false, 1000, 100, IStakeToken(address(stakeLocker1)));
    }
}
