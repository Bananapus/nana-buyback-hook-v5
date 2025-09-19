# JBBuybackHook
[Git Source](https://github.com/Bananapus/nana-buyback-hook-v5/blob/0ff73aee4ae7a3a75f75129bcf8bbef59b4c3bb1/src/JBBuybackHook.sol)

**Inherits:**
JBPermissioned, ERC2771Context, [IJBBuybackHook](/src/interfaces/IJBBuybackHook.sol/interface.IJBBuybackHook.md)

The buyback hook allows beneficiaries of a payment to a project to either:
- Get tokens by paying the project through its terminal OR
- Buy tokens from the configured Uniswap v3 pool.
Depending on which route would yield more tokens for the beneficiary. The project's reserved rate applies to either
route.

*Compatible with any `JBTerminal` and any project token that can be pooled on Uniswap v3.*

**Note:**
benediction: DEVS BENEDICAT ET PROTEGAT CONTRACTVS MEAM


## State Variables
### MAX_TWAP_WINDOW
Projects cannot specify a TWAP window longer than this constant.

*This serves to avoid excessively long TWAP windows that could lead to outdated pricing information and
higher gas costs due to increased computational requirements.*


```solidity
uint256 public constant override MAX_TWAP_WINDOW = 2 days;
```


### MIN_TWAP_WINDOW
Projects cannot specify a TWAP window shorter than this constant.

*This serves to avoid extremely short TWAP windows that could be manipulated or subject to high volatility.*


```solidity
uint256 public constant override MIN_TWAP_WINDOW = 2 minutes;
```


### TWAP_SLIPPAGE_DENOMINATOR
The denominator used when calculating TWAP slippage percent values.


```solidity
uint256 public constant override TWAP_SLIPPAGE_DENOMINATOR = 10_000;
```


### UNCERTAIN_TWAP_SLIPPAGE_TOLERANCE
The uncertain slippage tolerance allowed.

*This serves to avoid extremely low slippage tolerances that could result in failed swaps.*


```solidity
uint256 public constant override UNCERTAIN_TWAP_SLIPPAGE_TOLERANCE = 1050;
```


### DIRECTORY
The directory of terminals and controllers.


```solidity
IJBDirectory public immutable override DIRECTORY;
```


### PRICES
The contract that exposes price feeds.


```solidity
IJBPrices public immutable override PRICES;
```


### PROJECTS
The project registry.


```solidity
IJBProjects public immutable override PROJECTS;
```


### TOKENS
The token registry.


```solidity
IJBTokens public immutable override TOKENS;
```


### UNISWAP_V3_FACTORY
The address of the Uniswap v3 factory. Used to calculate pool addresses.


```solidity
address public immutable override UNISWAP_V3_FACTORY;
```


### WETH
The wETH contract.


```solidity
IWETH9 public immutable override WETH;
```


### poolOf
The Uniswap pool where a given project's token and terminal token pair are traded.


```solidity
mapping(uint256 projectId => mapping(address terminalToken => IUniswapV3Pool)) public override poolOf;
```


### projectTokenOf
The address of each project's token.


```solidity
mapping(uint256 projectId => address) public override projectTokenOf;
```


### twapWindowOf
The TWAP window for the given project. The TWAP window is the period of time over which the TWAP is
computed.


```solidity
mapping(uint256 projectId => uint256) public override twapWindowOf;
```


## Functions
### constructor


```solidity
constructor(
    IJBDirectory directory,
    IJBPermissions permissions,
    IJBPrices prices,
    IJBProjects projects,
    IJBTokens tokens,
    IWETH9 weth,
    address factory,
    address trustedForwarder
)
    JBPermissioned(permissions)
    ERC2771Context(trustedForwarder);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`directory`|`IJBDirectory`|The directory of terminals and controllers.|
|`permissions`|`IJBPermissions`|The permissions contract.|
|`prices`|`IJBPrices`|The contract that exposes price feeds.|
|`projects`|`IJBProjects`|The project registry.|
|`tokens`|`IJBTokens`|The token registry.|
|`weth`|`IWETH9`|The WETH contract.|
|`factory`|`address`|The address of the Uniswap v3 factory. Used to calculate pool addresses.|
|`trustedForwarder`|`address`|A trusted forwarder of transactions to this contract.|


### beforePayRecordedWith

The `IJBRulesetDataHook` implementation which determines whether tokens should be minted from the
project or bought from the pool.


```solidity
function beforePayRecordedWith(JBBeforePayRecordedContext calldata context)
    external
    view
    override
    returns (uint256 weight, JBPayHookSpecification[] memory hookSpecifications);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`context`|`JBBeforePayRecordedContext`|Payment context passed to the data hook by `terminalStore.recordPaymentFrom(...)`. `context.metadata` can specify a Uniswap quote and specify how much of the payment should be used to swap. If `context.metadata` does not specify a quote, one will be calculated based on the TWAP. If `context.metadata` does not specify how much of the payment should be used, the hook uses the full amount paid in.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`weight`|`uint256`|The weight to use. If tokens are being minted from the project, this is the original weight. If tokens are being bought from the pool, the weight is 0. If tokens are being minted AND bought from the pool, this weight is adjusted to take both into account.|
|`hookSpecifications`|`JBPayHookSpecification[]`|Specifications containing pay hooks, as well as the amount and metadata to send to them. Fulfilled by the terminal. If tokens are only being minted, `hookSpecifications` will be empty.|


### beforeCashOutRecordedWith

To fulfill the `IJBRulesetDataHook` interface.

*Pass cash out context back to the terminal without changes.*


```solidity
function beforeCashOutRecordedWith(JBBeforeCashOutRecordedContext calldata context)
    external
    pure
    override
    returns (uint256, uint256, uint256, JBCashOutHookSpecification[] memory hookSpecifications);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`context`|`JBBeforeCashOutRecordedContext`|The cash out context passed in by the terminal.|


### hasMintPermissionFor

Required by the `IJBRulesetDataHook` interfaces. Return false to not leak any permissions.


```solidity
function hasMintPermissionFor(uint256, JBRuleset memory, address) external pure override returns (bool);
```

### supportsInterface


```solidity
function supportsInterface(bytes4 interfaceId) public pure override returns (bool);
```

### _contextSuffixLength

*`ERC-2771` specifies the context as being a single address (20 bytes).*


```solidity
function _contextSuffixLength() internal view override(ERC2771Context, Context) returns (uint256);
```

### _getQuote

Get a quote based on the TWAP, using the TWAP window and slippage tolerance for the specified project.


```solidity
function _getQuote(
    uint256 projectId,
    address projectToken,
    uint256 amountIn,
    address terminalToken
)
    internal
    view
    returns (uint256 amountOut);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`projectId`|`uint256`|The ID of the project which the swap is associated with.|
|`projectToken`|`address`|The project token being swapped for.|
|`amountIn`|`uint256`|The number of terminal tokens being used to swap.|
|`terminalToken`|`address`|The terminal token being paid in and used to swap.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`amountOut`|`uint256`|The minimum number of tokens to receive based on the TWAP and its params.|


### _getSlippageTolerance

Get the slippage tolerance for a given amount in and liquidity.


```solidity
function _getSlippageTolerance(
    uint256 amountIn,
    uint128 liquidity,
    address projectToken,
    address terminalToken,
    int24 arithmeticMeanTick
)
    internal
    pure
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amountIn`|`uint256`|The amount in to get the slippage tolerance for.|
|`liquidity`|`uint128`|The liquidity to get the slippage tolerance for.|
|`projectToken`|`address`|The project token to get the slippage tolerance for.|
|`terminalToken`|`address`|The terminal token to get the slippage tolerance for.|
|`arithmeticMeanTick`|`int24`|The arithmetic mean tick to get the slippage tolerance for.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|slippageTolerance The slippage tolerance for the given amount in and liquidity.|


### _msgData

The calldata. Preferred to use over `msg.data`.


```solidity
function _msgData() internal view override(ERC2771Context, Context) returns (bytes calldata);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes`|calldata The `msg.data` of this call.|


### _msgSender

The message's sender. Preferred to use over `msg.sender`.


```solidity
function _msgSender() internal view override(ERC2771Context, Context) returns (address sender);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`sender`|`address`|The address which sent this call.|


### afterPayRecordedWith

Swap the specified amount of terminal tokens for project tokens, using any leftover terminal tokens to
mint from the project.

*This function is only called if the minimum return from the swap exceeds the return from minting by paying
the project.
If the swap reverts (due to slippage, insufficient liquidity, or something else),
then the hook mints the number of tokens which a payment to the project would have minted.*


```solidity
function afterPayRecordedWith(JBAfterPayRecordedContext calldata context) external payable override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`context`|`JBAfterPayRecordedContext`|The pay context passed in by the terminal.|


### setPoolFor

Set the pool to use for a given project and terminal token (the default for the project's token <->
terminal token pair).

*Uses create2 for callback auth and to allow adding pools which haven't been deployed yet.
This can be called by the project's owner or an address which has the `JBPermissionIds.SET_BUYBACK_POOL`
permission from the owner.*


```solidity
function setPoolFor(
    uint256 projectId,
    uint24 fee,
    uint256 twapWindow,
    address terminalToken
)
    external
    returns (IUniswapV3Pool newPool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`projectId`|`uint256`|The ID of the project to set the pool for.|
|`fee`|`uint24`|The fee used in the pool being set, as a fixed-point number of basis points with 2 decimals. A 0.01% fee is `100`, a 0.05% fee is `500`, a 0.3% fee is `3000`, and a 1% fee is `10000`.|
|`twapWindow`|`uint256`|The period of time over which the TWAP is computed.|
|`terminalToken`|`address`|The address of the terminal token that payments to the project are made in.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`newPool`|`IUniswapV3Pool`|The pool that was set for the project and terminal token.|


### setTwapWindowOf

Change the TWAP window for a project.
The TWAP window is the period of time over which the TWAP is computed.

*This can be called by the project's owner or an address with `JBPermissionIds.SET_BUYBACK_TWAP`
permission from the owner.*


```solidity
function setTwapWindowOf(uint256 projectId, uint256 newWindow) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`projectId`|`uint256`|The ID of the project to set the TWAP window of.|
|`newWindow`|`uint256`|The new TWAP window.|


### uniswapV3SwapCallback

The Uniswap v3 pool callback where the token transfer is expected to happen.


```solidity
function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount0Delta`|`int256`|The amount of token 0 being used for the swap.|
|`amount1Delta`|`int256`|The amount of token 1 being used for the swap.|
|`data`|`bytes`|Data passed in by the swap operation.|


### _swap

Swap the terminal token to receive project tokens.


```solidity
function _swap(
    JBAfterPayRecordedContext calldata context,
    bool projectTokenIs0,
    IJBController controller
)
    internal
    returns (uint256 amountReceived);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`context`|`JBAfterPayRecordedContext`|The `afterPayRecordedContext` passed in by the terminal.|
|`projectTokenIs0`|`bool`|A flag indicating whether the pool references the project token as the first in the pair.|
|`controller`|`IJBController`|The controller used to mint and burn tokens.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`amountReceived`|`uint256`|The amount of project tokens received from the swap.|


## Errors
### JBBuybackHook_CallerNotPool

```solidity
error JBBuybackHook_CallerNotPool(address caller);
```

### JBBuybackHook_InsufficientPayAmount

```solidity
error JBBuybackHook_InsufficientPayAmount(uint256 swapAmount, uint256 totalPaid);
```

### JBBuybackHook_InvalidTwapWindow

```solidity
error JBBuybackHook_InvalidTwapWindow(uint256 value, uint256 min, uint256 max);
```

### JBBuybackHook_PoolAlreadySet

```solidity
error JBBuybackHook_PoolAlreadySet(IUniswapV3Pool pool);
```

### JBBuybackHook_SpecifiedSlippageExceeded

```solidity
error JBBuybackHook_SpecifiedSlippageExceeded(uint256 amount, uint256 minimum);
```

### JBBuybackHook_TerminalTokenIsProjectToken

```solidity
error JBBuybackHook_TerminalTokenIsProjectToken(address terminalToken, address projectToken);
```

### JBBuybackHook_Unauthorized

```solidity
error JBBuybackHook_Unauthorized(address caller);
```

### JBBuybackHook_ZeroProjectToken

```solidity
error JBBuybackHook_ZeroProjectToken();
```

### JBBuybackHook_ZeroTerminalToken

```solidity
error JBBuybackHook_ZeroTerminalToken();
```

