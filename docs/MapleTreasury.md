

## Functions:
[`constructor(address _mpl, address _fundsToken, address _uniswapRouter, address _globals)`](#MapleTreasury-constructor-address-address-address-address-)
[`fallback()`](#MapleTreasury-fallback--)
[`receive()`](#MapleTreasury-receive--)
[`setFundsToken(address _newFundsToken)`](#MapleTreasury-setFundsToken-address-)
[`passThroughFundsToken()`](#MapleTreasury-passThroughFundsToken--)
[`convertERC20(address _asset)`](#MapleTreasury-convertERC20-address-)
[`convertETH(uint256 _amountOut, uint256 _amountIn)`](#MapleTreasury-convertETH-uint256-uint256-)

## Events:
[`ERC20Conversion(address _asset, address _by, uint256 _amountIn, uint256 _amountOut)`](#MapleTreasury-ERC20Conversion-address-address-uint256-uint256-)
[`ETHConversion(address _by, uint256 _amountIn, uint256 _amountOut)`](#MapleTreasury-ETHConversion-address-uint256-uint256-)
[`PassThrough(address _by, uint256 _amount)`](#MapleTreasury-PassThrough-address-uint256-)
[`FundsTokenModified(address _by, address _newFundsToken)`](#MapleTreasury-FundsTokenModified-address-address-)

## <u>Functions</u>

### `constructor(address _mpl, address _fundsToken, address _uniswapRouter, address _globals)`
Instantiates the MapleTreasury contract.
        @param  _mpl is the MapleToken contract.
        @param  _fundsToken is the fundsToken of MapleToken contract.
        @param  _uniswapRouter is the official UniswapV2 router contract.
        @param  _globals is the MapleGlobals.sol contract.

### `fallback()`
No description

### `receive()`
No description

### `setFundsToken(address _newFundsToken)`
Adjust the token to convert assets to (and then send to MapleToken).
        @param _newFundsToken The new FundsToken with respect to MapleToken ERC-2222.

### `passThroughFundsToken()`
Passes through the current fundsToken to MapleToken.

### `convertERC20(address _asset)`
Convert an ERC-20 asset through Uniswap via bilateral transaction (two asset path).
        @param _asset The ERC-20 asset to convert.

### `convertETH(uint256 _amountOut, uint256 _amountIn)`
Convert ETH through Uniswap via bilateral transaction (two asset path).
        @param _amountOut The amount out expected.
        @param _amountIn  The amount in to convert.

## <u>Events</u>

### `ERC20Conversion(address _asset, address _by, uint256 _amountIn, uint256 _amountOut)`
Fired when an ERC-20 asset is converted to fundsToken and transferred to mpl.
        @param _asset     The asset that is converted.
        @param _by        The msg.sender calling the conversion function.
        @param _amountIn  The amount of _asset converted to fundsToken.
        @param _amountOut The amount of fundsToken received for _asset conversion.

### `ETHConversion(address _by, uint256 _amountIn, uint256 _amountOut)`
Fired when ETH is converted to fundsToken and transferred to mpl.
        @param _by        The msg.sender calling the conversion function.
        @param _amountIn  The amount of ETH converted to fundsToken.
        @param _amountOut The amount of fundsToken received for ETH conversion.

### `PassThrough(address _by, uint256 _amount)`
Fired when fundsToken is passed through to mpl.
        @param _by        The msg.sender calling the passThrough function.
        @param _amount    The amount of fundsToken passed through.

### `FundsTokenModified(address _by, address _newFundsToken)`
Fired when fundsToken is modified for this contract.
        @param _by            The msg.sender calling the passThrough function.
        @param _newFundsToken The new fundsToken to convert to.
