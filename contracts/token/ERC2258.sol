// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/// @title ERC2258 implements base level ERC2258 functionality for custodial functionality
abstract contract ERC2258 is ERC20 {

    using SafeMath for uint256;

    mapping(address => mapping(address => uint256)) public custodyAllowance;           // Amount of funds that are "locked" at a certain address
    mapping(address => uint256)                     public totalCustodyAllowance;      // Total amount of funds that are "locked" for a given user, cannot be greater than balance

    event         CustodyTransfer(address indexed custodian, address indexed from, address indexed to, uint256 amount);
    event CustodyAllowanceChanged(address indexed tokenHolder, address indexed custodian, uint256 oldAllowance, uint256 newAllowance);

    /**
        @dev   Increase the custody allowance for a given `custodian` corresponding to `msg.sender`.
        @dev   It emits a `CustodyAllowanceChanged` event.
        @param custodian Address which will act as custodian of a given `amount` for a tokenHolder.
        @param amount    Number of FDTs custodied by the custodian.
    */
    function increaseCustodyAllowance(address custodian, uint256 amount) external virtual {
        uint256 oldAllowance      = custodyAllowance[msg.sender][custodian];
        uint256 newAllowance      = oldAllowance.add(amount);
        uint256 newTotalAllowance = totalCustodyAllowance[msg.sender].add(amount);

        require(custodian != address(0),                     "ERC2258:BAD_CUST");
        require(amount    != uint256(0),                     "ERC2258:BAD_AMT");
        require(newTotalAllowance <= balanceOf(msg.sender),  "ERC2258:INSUF_BAL");
        
        custodyAllowance[msg.sender][custodian] = newAllowance;
        totalCustodyAllowance[msg.sender]       = newTotalAllowance;

        emit CustodyAllowanceChanged(msg.sender, custodian, oldAllowance, newAllowance);
    }

    /**
        @dev   `from` and `to` should always be equal in this implementation.
        @dev   This means that the custodian can only decrease their own allowance and unlock funds for the original owner.
        @dev   It emits a `CustodyTransfer` event.
        @dev   It emits a `CustodyAllowanceChanged` event.
        @param from   Address which holds the funds.
        @param to     Address which will be the new owner of the `amount` of funds transferred.
        @param amount Amount of funds to be transferred.
    */
    function transferByCustodian(address from, address to, uint256 amount) external virtual {
        uint256 oldAllowance = custodyAllowance[from][msg.sender];
        uint256 newAllowance = oldAllowance.sub(amount);

        require(to == from,             "ERC2258:BAD_REC");
        require(amount != uint256(0),   "ERC2258:BAD_AMT");

        custodyAllowance[from][msg.sender] = newAllowance;
        totalCustodyAllowance[from]        = totalCustodyAllowance[from].sub(amount);

        emit CustodyTransfer(msg.sender, from, to, amount);
        emit CustodyAllowanceChanged(msg.sender, to, oldAllowance, newAllowance);
    }
}
