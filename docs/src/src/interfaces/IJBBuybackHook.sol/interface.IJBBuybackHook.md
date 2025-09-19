# IJBBuybackHook
[Git Source](https://github.com/Bananapus/nana-buyback-hook-v5/blob/0ff73aee4ae7a3a75f75129bcf8bbef59b4c3bb1/src/interfaces/IJBBuybackHook.sol)

**Inherits:**
IJBPayHook, IJBRulesetDataHook, IUniswapV3SwapCallback


## Functions
### DIRECTORY


```solidity
function DIRECTORY() external view returns (IJBDirectory);
```

### PRICES


```solidity
function PRICES() external view returns (IJBPrices);
```

### PROJECTS


```solidity
function PROJECTS() external view returns (IJBProjects);
```

### TOKENS


```solidity
function TOKENS() external view returns (IJBTokens);
```

### MAX_TWAP_WINDOW


```solidity
function MAX_TWAP_WINDOW() external view returns (uint256);
```

### MIN_TWAP_WINDOW


```solidity
function MIN_TWAP_WINDOW() external view returns (uint256);
```

### TWAP_SLIPPAGE_DENOMINATOR


```solidity
function TWAP_SLIPPAGE_DENOMINATOR() external view returns (uint256);
```

### UNCERTAIN_TWAP_SLIPPAGE_TOLERANCE


```solidity
function UNCERTAIN_TWAP_SLIPPAGE_TOLERANCE() external view returns (uint256);
```

### UNISWAP_V3_FACTORY


```solidity
function UNISWAP_V3_FACTORY() external view returns (address);
```

### WETH


```solidity
function WETH() external view returns (IWETH9);
```

### poolOf


```solidity
function poolOf(uint256 projectId, address terminalToken) external view returns (IUniswapV3Pool pool);
```

### projectTokenOf


```solidity
function projectTokenOf(uint256 projectId) external view returns (address projectTokenOf);
```

### twapWindowOf


```solidity
function twapWindowOf(uint256 projectId) external view returns (uint256 window);
```

### setPoolFor


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

### setTwapWindowOf


```solidity
function setTwapWindowOf(uint256 projectId, uint256 newWindow) external;
```

## Events
### Swap

```solidity
event Swap(
    uint256 indexed projectId, uint256 amountToSwapWith, IUniswapV3Pool pool, uint256 amountReceived, address caller
);
```

### Mint

```solidity
event Mint(uint256 indexed projectId, uint256 leftoverAmount, uint256 tokenCount, address caller);
```

### PoolAdded

```solidity
event PoolAdded(uint256 indexed projectId, address indexed terminalToken, address pool, address caller);
```

### TwapWindowChanged

```solidity
event TwapWindowChanged(uint256 indexed projectId, uint256 oldWindow, uint256 newWindow, address caller);
```

