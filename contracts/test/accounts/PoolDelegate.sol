// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { PoolDelegate as PoolDelegateOfPools }        from "../../../modules/pool/contracts/test/accounts/PoolDelegate.sol";
import { PoolDelegate as PoolDelegateOfStakeLockers } from "../../../modules/stake-locker/contracts/test/accounts/PoolDelegate.sol";
import { Staker as StakerOfStakeLockers }             from "../../../modules/stake-locker/contracts/test/accounts/Staker.sol";

contract PoolDelegate is PoolDelegateOfPools, PoolDelegateOfStakeLockers, StakerOfStakeLockers {}
