// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { SafeMath } from "../../../../lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import { ERC20 }    from "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import { IERC2258 } from "./interfaces/IERC2258.sol";

/// @title ERC2258 implements the basic level functionality for a token capable of custodial ownership.
contract ERC2258 is IERC2258, ERC20 {

    using SafeMath       for uint256;

    mapping(address => mapping(address => uint256)) public override custodyAllowance;
    mapping(address => uint256)                     public override totalCustodyAllowance;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) public { }

    function increaseCustodyAllowance(address custodian, uint256 amount) external override {
        uint256 oldAllowance      = custodyAllowance[msg.sender][custodian];
        uint256 newAllowance      = oldAllowance.add(amount);
        uint256 newTotalAllowance = totalCustodyAllowance[msg.sender].add(amount);

        require(newTotalAllowance <= balanceOf(msg.sender), "ERC2258:INSUF_BALANCE");

        custodyAllowance[msg.sender][custodian] = newAllowance;
        totalCustodyAllowance[msg.sender]       = newTotalAllowance;

        emit CustodyAllowanceChanged(msg.sender, custodian, oldAllowance, newAllowance);
    }

    function transferByCustodian(address from, address to, uint256 amount) external override {
        uint256 oldAllowance = custodyAllowance[from][msg.sender];
        uint256 newAllowance = oldAllowance.sub(amount);

        custodyAllowance[from][msg.sender] = newAllowance;
        uint256 newTotalAllowance          = totalCustodyAllowance[from].sub(amount);
        totalCustodyAllowance[from]        = newTotalAllowance;
        
        emit CustodyTransfer(msg.sender, from, to, amount);
        emit CustodyAllowanceChanged(from, msg.sender, oldAllowance, newAllowance);
    }

}
