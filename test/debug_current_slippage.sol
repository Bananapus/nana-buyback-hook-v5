// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {mulDiv} from "@prb/math/src/Common.sol";

contract DebugCurrentSlippage is Test {
    uint256 constant TWAP_SLIPPAGE_DENOMINATOR = 10_000;
    uint256 constant MIN_TWAP_SLIPPAGE_TOLERANCE = 1050;

    function testCurrentSlippageCalculation() public {
        // Test with realistic values from the fork tests
        uint256 amountIn = 1 ether; // 1 ETH
        uint128 liquidity = 10_000_000 ether; // 10M ETH liquidity

        // From the test: sqrtPriceX96 = 300_702_666_377_442_711_115_399_168
        // This corresponds to 1 ETH = 69420 JBX
        uint160 sqrtPriceX96 = 300_702_666_377_442_711_115_399_168;

        // Calculate the tick from sqrtPriceX96
        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        console.log("Tick:", tick);

        // Test both directions with current implementation
        testCurrentDirection(amountIn, liquidity, sqrtPriceX96, true); // zeroForOne = true
        testCurrentDirection(amountIn, liquidity, sqrtPriceX96, false); // zeroForOne = false

        // Test with smaller amounts that might be used in fork tests
        console.log("\n=== Testing with smaller amounts ===");
        uint256 smallAmountIn = 16_821; // From fork test failure
        testCurrentDirection(smallAmountIn, liquidity, sqrtPriceX96, true);
        testCurrentDirection(smallAmountIn, liquidity, sqrtPriceX96, false);
    }

    function testCurrentDirection(uint256 amountIn, uint128 liquidity, uint160 sqrtP, bool zeroForOne) internal {
        console.log("\n=== Testing direction zeroForOne:", zeroForOne);
        console.log("Amount in:", amountIn);
        console.log("Liquidity:", liquidity);

        // Current implementation: base calculation
        uint256 base = mulDiv(amountIn, 2 * TWAP_SLIPPAGE_DENOMINATOR, uint256(liquidity));
        console.log("Base (before sqrtP normalization):", base);
        console.log("Base in %:", (base * 100) / TWAP_SLIPPAGE_DENOMINATOR);

        // Current implementation: sqrtP normalization
        uint256 slippageTolerance;
        if (zeroForOne) {
            slippageTolerance = mulDiv(base, uint256(sqrtP), uint256(1) << 96);
        } else {
            slippageTolerance = mulDiv(base, uint256(1) << 96, uint256(sqrtP));
        }

        console.log("Slippage tolerance (after sqrtP normalization):", slippageTolerance);
        console.log("Slippage tolerance in %:", (slippageTolerance * 100) / TWAP_SLIPPAGE_DENOMINATOR);

        // Apply min/max bounds
        if (slippageTolerance > TWAP_SLIPPAGE_DENOMINATOR) {
            slippageTolerance = TWAP_SLIPPAGE_DENOMINATOR;
            console.log("Capped at max (100%)");
        } else if (slippageTolerance < MIN_TWAP_SLIPPAGE_TOLERANCE) {
            slippageTolerance = MIN_TWAP_SLIPPAGE_TOLERANCE;
            console.log("Capped at min (10.5%)");
        }

        console.log("Final slippage tolerance:", slippageTolerance);
        console.log("Final slippage tolerance in %:", (slippageTolerance * 100) / TWAP_SLIPPAGE_DENOMINATOR);

        // Test what happens if we use a lower minimum
        console.log("\n--- Testing with MIN_TWAP_SLIPPAGE_TOLERANCE = 50 (0.5%) ---");
        uint256 lowMinSlippage = 50;
        uint256 slippageWithLowMin = slippageTolerance;
        if (slippageTolerance < lowMinSlippage) {
            slippageWithLowMin = lowMinSlippage;
            console.log("Would be capped at 0.5%");
        }
        console.log("Slippage with 0.5% min:", slippageWithLowMin);
        console.log("Slippage with 0.5% min in %:", (slippageWithLowMin * 100) / TWAP_SLIPPAGE_DENOMINATOR);
    }
}
