// SPDX-License-Identifier: GPL-2.0-or-later
// Source: https://github.com/Uniswap/v3-periphery/blob/main/contracts/libraries/PoolAddress.sol
pragma solidity >=0.5.0;

/// @title Provides functions for deriving a pool address based on a factory address, the tokens traded in the pool, and the fee
library PoolAddress {
    bytes32 internal constant POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

    /// @notice The identifying key of the pool.
    struct PoolKey {
        address token0;
        address token1;
        uint24 fee;
    }

    /// @notice Get the pool key, which is used to compute the pool address.
    /// @dev The pool key is the tokens (in order) with the matched fee levels.
    /// @param tokenA The first token of a pool, unsorted.
    /// @param tokenB The second token of a pool, unsorted.
    /// @param fee The fee level of the pool.
    /// @return Poolkey The pool details with `token0` and `token1` in order.
    function getPoolKey(address tokenA, address tokenB, uint24 fee) internal pure returns (PoolKey memory) {
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
        return PoolKey({token0: tokenA, token1: tokenB, fee: fee});
    }

    /// @notice Deterministically compute the pool address given a factory address and a `PoolKey`.
    /// @param factory The Uniswap v3 factory contract address.
    /// @param key The `PoolKey` to get the pool for.
    /// @return pool The address of the Uniswap v3 pool.
    function computeAddress(address factory, PoolKey memory key) internal pure returns (address pool) {
        require(key.token0 < key.token1);
        pool = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            factory,
                            keccak256(abi.encode(key.token0, key.token1, key.fee)),
                            POOL_INIT_CODE_HASH
                        )
                    )
                )
            )
        );
    }
}
