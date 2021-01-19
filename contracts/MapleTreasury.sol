// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IGlobals.sol";
import "./interfaces/IUniswapRouter.sol";
import "./interfaces/IMapleToken.sol";

contract MapleTreasury {

	using SafeMath for uint256;

    address public mpl;     // MapleToken.sol contract.
    address public fundsToken;     // _fundsToken value in the MapleToken.sol contract.
    address public uniswapRouter;  // Official UniswapV2 router contract.
    address public globals;   // MapleGlobals.sol contract.

    /**
        @dev Instantiates the MapleTreasury contract.
        @param  _mpl is the MapleToken contract.
        @param  _fundsToken is the fundsToken of MapleToken contract.
        @param  _uniswapRouter is the official UniswapV2 router contract.
        @param  _globals is the MapleGlobals.sol contract.
    */
    constructor(
        address _mpl, 
        address _fundsToken, 
        address _uniswapRouter,
        address _globals
    ) public {
        mpl           = _mpl;
        fundsToken    = _fundsToken;
        uniswapRouter = _uniswapRouter;
        globals       = _globals;
    }

    /**
        @dev Fired when an ERC-20 asset is converted to fundsToken and transferred to mpl.
        @param _asset     The asset that is converted.
        @param _by        The msg.sender calling the conversion function.
        @param _amountIn  The amount of _asset converted to fundsToken.
        @param _amountOut The amount of fundsToken received for _asset conversion.
    */
    event ERC20Conversion(
        address _asset,
        address _by,
        uint256 _amountIn,
        uint256 _amountOut
    );

    /**
        @dev Fired when ETH is converted to fundsToken and transferred to mpl.
        @param _by        The msg.sender calling the conversion function.
        @param _amountIn  The amount of ETH converted to fundsToken.
        @param _amountOut The amount of fundsToken received for ETH conversion.
    */
    event ETHConversion(
        address _by,
        uint256 _amountIn,
        uint256 _amountOut
    );

    /**
        @dev Fired when fundsToken is passed through to mpl.
        @param _by        The msg.sender calling the passThrough function.
        @param _amount    The amount of fundsToken passed through.
    */
    event PassThrough(
        address _by,
        uint256 _amount
    );

    /**
        @dev Fired when fundsToken is modified for this contract.
        @param _by            The msg.sender calling the passThrough function.
        @param _newFundsToken The new fundsToken to convert to.
    */
    // TODO: Consider why this would be changed? Seems this would lead to critical erros.
    event FundsTokenModified(
        address _by,
        address _newFundsToken
    );

    modifier isGovernor() {
        require(msg.sender == IGlobals(globals).governor(), "msg.sender is not Governor");
        _;
    }
  
    fallback () external payable { }
    receive  () external payable { }

    /**
        @dev Adjust the token to convert assets to (and then send to MapleToken).
        @param _newFundsToken The new FundsToken with respect to MapleToken ERC-2222.
    */
    // TODO: Consider why this would be changed? Seems this would lead to critical erros.
    function setFundsToken(address _newFundsToken) isGovernor public {
        fundsToken = _newFundsToken;
    }

    /**
        @dev Passes through the current fundsToken to MapleToken.
    */
    function passThroughFundsToken() isGovernor public {
        IERC20 _fundsToken = IERC20(fundsToken);
        require(
            _fundsToken.transfer(mpl, _fundsToken.balanceOf(address(this))), 
            "MapleTreasury::passThroughFundsToken:FUNDS_RECEIVE_TRANSFER_ERROR"
        );
        emit PassThrough(msg.sender, _fundsToken.balanceOf(address(this)));
    }

    /**
    TODO:  Implement price oracle to ensure best quality execution (1% slippage) ...
            and also to prevent front-running of transactions.
            The price feed should be used for USDC conversion, supplied in the ...
            2nd parameter of the swapExactTokensForTokens() function.
    */

    /**
        @dev Convert an ERC-20 asset through Uniswap via bilateral transaction (two asset path).
        @param _asset The ERC-20 asset to convert.
    */
    function convertERC20(address _asset) isGovernor public {
        require(_asset != fundsToken, "MapleTreasury::convertERC20:ERR_ASSET");
        require(
            IERC20(_asset).approve(uniswapRouter, IERC20(_asset).balanceOf(address(this))), 
            "MapleTreasury::convertERC20:ROUTER_APPROVE_FAIL"
        );
        address[] memory path = new address[](2);
        path[0] = _asset;
        path[1] = fundsToken;
        uint[] memory returnAmounts = IUniswapRouter(uniswapRouter).swapExactTokensForTokens(
            IERC20(_asset).balanceOf(address(this)),
            0,
            path,
            mpl,
            block.timestamp + 1
        );
        IMapleToken(mpl).updateFundsReceived();
        emit ERC20Conversion(
            _asset,
            msg.sender,
            returnAmounts[0],
            returnAmounts[1]
        );
    }

    /**
    TODO:  Implement price oracle to ensure best quality execution (1% slippage) ...
            and also to prevent front-running of transactions.
            The price feed should be used for USDC conversion, supplied in the ...
            2nd parameter of the swapETHForExactTokens() function.
    */

    /**
        @dev Convert ETH through Uniswap via bilateral transaction (two asset path).
        @param _amountOut The amount out expected.
        @param _amountIn  The amount in to convert.
    */
    function convertETH(uint256 _amountOut, uint256 _amountIn) isGovernor public {
        address[] memory path = new address[](2);
        path[0] = IUniswapRouter(uniswapRouter).WETH();
        path[1] = fundsToken;
        uint256[] memory returnAmounts = IUniswapRouter(uniswapRouter).swapETHForExactTokens{value: _amountIn}(
            _amountOut,
            path,
            mpl,
            block.timestamp + 1
        );
        IMapleToken(mpl).updateFundsReceived();
        emit ETHConversion(
            msg.sender,
            returnAmounts[0],
            returnAmounts[1]
        );
    }

}
