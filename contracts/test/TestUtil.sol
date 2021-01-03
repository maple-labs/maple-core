// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "lib/ds-test/contracts/test.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "../interfaces/ILoanVault.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
}

interface User {
    function approve(address, uint256) external;
}

// TODO: Create master contracts for the following "users":
//  (1) PoolDelegate
//  (2) Borrower
//  (3) Liquidity Provider
//  (4) Individual Lender
//  (5) Staker

contract TestUtil is DSTest {
    Hevm hevm;

    struct Token {
        address addr; // ERC20 Mainnet address
        uint256 slot; // Balance storage slot
    }

    mapping (bytes32 => Token) tokens;

    address constant DAI  = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address constant BPOOL_FACTORY = 0x9424B1412450D0f8Fc2255FAf6046b98213B76Bd; // Balancer pool factory

    uint256 constant WAD = 10 ** 18;

    bytes20 constant CHEAT_CODE = bytes20(uint160(uint256(keccak256("hevm cheat code"))));

    constructor() public {
        hevm = Hevm(address(CHEAT_CODE));

        tokens["DAI"].addr  = DAI;
        tokens["DAI"].slot  = 2;
        tokens["USDC"].addr = USDC;
        tokens["USDC"].slot = 9;
        tokens["WETH"].addr = WETH;
        tokens["WETH"].slot = 3;
    }

    // Manipulate mainnet ERC20 balance
    function mint(bytes32 symbol, address who, uint256 amt) public {
        address addr = tokens[symbol].addr;
        uint256 slot  = tokens[symbol].slot;
        uint256 bal = IERC20(addr).balanceOf(who);

        hevm.store(
            addr,
            keccak256(abi.encode(who, slot)), // Mint tokens
            bytes32(bal + amt)
        );

        assertEq(IERC20(addr).balanceOf(who), bal + amt); // Assert new balance
    }
    
    // // Make payment on any given LoanVault.
    // function makePayment(address _vault, address _borrower) public {

    //     // Create loanVault object and ensure it's accepting payments.
    //     LoanVault loanVault = LoanVault(_vault);
    //     assertEq(uint256(loanVault.loanState()), 1);  // Loan state: (1) Active

    //     // Warp to *300 seconds* before next payment is due
    //     hevm.warp(loanVault.nextPaymentDue() - 300);
    //     assertEq(block.timestamp, loanVault.nextPaymentDue() - 300);

    //     // Make payment.
    //     address _assetRequested = loanVault.assetRequested();
    //     (uint _amt,,,) = loanVault.getNextPayment();

    //     User(_borrower).approve(_assetRequested, _vault, _amt);

    //     assertTrue(ali.try_makePayment(_vault));
    // }
}
