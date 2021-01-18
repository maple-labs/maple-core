// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

interface SynthSwap {
    function synth_pools(address) external view returns(address);
    function swappable_synth(address) external view returns(address);
    function get_estimated_swap_amount(address, address, uint256) external view returns(uint256);
    function get_swap_into_synth_amount(address, address, uint256) external view returns(uint256);
    function swap_into_synth(address, address, uint256, uint256) external payable returns(uint256);
}

contract CrossAssetSwapTest is TestUtil {

    address constant public SYNTH_SWAP = 0x58A3c68e2D3aAf316239c003779F71aCb870Ee47;

    SynthSwap synthSwap;

    function setUp() public {
        synthSwap = SynthSwap(SYNTH_SWAP);
    }

    function test_cross_asset_swap() public {
        // address swappableSynth = synthSwap.swappable_synth(DAI);
        // assertEq(synthSwap.swappable_synth(DAI), address(0));
        // assertEq(synthSwap.synth_pools(swappableSynth), address(0));
        // address synthPool = synthSwap.synth_pools(swappableSynth);

        // uint estAmount = synthSwap.get_estimated_swap_amount(DAI, WBTC, 100_000_000 * 10 ** 18);
        // log_named_uint("estAmount", estAmount);

        // assertEq(synthSwap.swappable_synth(WETH), address(1));

        mint("DAI", address(this), 200_000_000 * 10 ** 18);

        address sbtc = synthSwap.swappable_synth(WBTC);
        assertEq(sbtc, address(2));

        uint256 expected = synthSwap.get_swap_into_synth_amount(DAI, sbtc, 100_000_000 * 10 ** 18);
        uint256 tokenId  = synthSwap.swap_into_synth(DAI, sbtc, 100_000_000 * 10 ** 18, expected);

        assertEq(expected, 1);
        assertEq(tokenId, 2);
    }   
}
