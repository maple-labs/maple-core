// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { Governor as GovernorOfGlobals }    from "../../../modules/globals/contracts/test/accounts/Governor.sol";
import { Governor as GovernorOfLoans }      from "../../../modules/loan/contracts/test/accounts/Governor.sol";
import { Governor as GovernorOfMplRewards } from "../../../modules/mpl-rewards/contracts/test/accounts/Governor.sol";
import { Governor as GovernorOfPools }      from "../../../modules/pool/contracts/test/accounts/Governor.sol";
import { Governor as GovernorOfTreasury }   from "../../../modules/treasury/contracts/test/accounts/Governor.sol";

contract Governor is GovernorOfGlobals, GovernorOfLoans, GovernorOfMplRewards, GovernorOfPools, GovernorOfTreasury {}
