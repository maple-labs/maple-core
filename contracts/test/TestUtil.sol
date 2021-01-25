// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "lib/ds-test/contracts/test.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "../interfaces/ILoan.sol";

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

    address constant DAI   = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC  = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH  = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant WBTC  = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant CDAI  = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    address constant CUSDC = 0x39AA39c021dfbaE8faC545936693aC917d5E7563;

    address constant BPOOL_FACTORY        = 0x9424B1412450D0f8Fc2255FAf6046b98213B76Bd; // Balancer pool factory
    address constant UNISWAP_V2_ROUTER_02 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // Uniswap V2 Router
    address constant ONE_INCH_DEX         = 0xC586BeF4a0992C495Cf22e1aeEE4E446CECDee0E; // OneInch DEX

    uint256 constant USD = 10 ** 6;  // USDC precision decimals
    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;


    bytes20 constant CHEAT_CODE = bytes20(uint160(uint256(keccak256("hevm cheat code"))));

    constructor() public {
        hevm = Hevm(address(CHEAT_CODE));

        tokens["DAI"].addr  = DAI;
        tokens["DAI"].slot  = 2;
        tokens["USDC"].addr = USDC;
        tokens["USDC"].slot = 9;
        tokens["WETH"].addr = WETH;
        tokens["WETH"].slot = 3;
        tokens["WBTC"].addr = WBTC;
        tokens["WBTC"].slot = 0;
        tokens["CDAI"].addr = CDAI;
        tokens["CDAI"].slot = 14;
        tokens["CUSDC"].addr = CUSDC;
        tokens["CUSDC"].slot = 15;
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

    // Verify equality within accuracy decimals
    function withinPrecision(uint256 val0, uint256 val1, uint256 accuracy) public {
        uint diff  = val0 > val1 ? val0 - val1 : val1 - val0;
        bool check = ((diff * RAY) / val0) < (RAY / 10 ** accuracy);   

        if (!check){
            emit log_named_uint("Error: approx a == b not satisfied, accuracy digits ", accuracy);
            emit log_named_uint("  Expected", val0);
            emit log_named_uint("    Actual", val1);
            fail();
        }
    }

    // function test_cheat_code_for_slot() public {
    //     address CDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    
    //     uint256 i = 0;

    //     while(IERC20(CDAI).balanceOf(address(this)) == 0) {
    //         hevm.store(
    //             CDAI,
    //             keccak256(abi.encode(address(this), i)), // Mint tokens
    //             bytes32(uint256(100))
    //         );
    //         if(IERC20(CDAI).balanceOf(address(this)) == 100) {
    //             log_named_uint("slot", i);
    //         }
    //         i += 1;
    //     }
    //     // assertTrue(false);
    // }
    
    // // Make payment on any given Loan.
    // function makePayment(address _vault, address _borrower) public {

    //     // Create loanVault object and ensure it's accepting payments.
    //     Loan loanVault = Loan(_vault);
    //     assertEq(uint256(loanVault.loanState()), 1);  // Loan state: (1) Active

    //     // Warp to *300 seconds* before next payment is due
    //     hevm.warp(loanVault.nextPaymentDue() - 300);
    //     assertEq(block.timestamp, loanVault.nextPaymentDue() - 300);

    //     // Make payment.
    //     address _loanAsset = loanVault.loanAsset();
    //     (uint _amt,,,) = loanVault.getNextPayment();

    //     User(_borrower).approve(_loanAsset, _vault, _amt);

    //     assertTrue(ali.try_makePayment(_vault));
    // }
}
