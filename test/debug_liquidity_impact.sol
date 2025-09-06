// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {mulDiv} from "@prb/math/src/Common.sol";

contract DebugLiquidityImpact is Test {
    uint256 constant TWAP_SLIPPAGE_DENOMINATOR = 10_000;
    uint256 constant MIN_TWAP_SLIPPAGE_TOLERANCE = 1050;

    function testLiquidityImpact() public {
        uint256 amountIn = 1 ether; // 1 ETH

        // Test with different liquidity levels
        uint128[] memory liquidityLevels = new uint128[](5);
        liquidityLevels[0] = 1000 ether; // 1K ETH
        liquidityLevels[1] = 10_000 ether; // 10K ETH
        liquidityLevels[2] = 100_000 ether; // 100K ETH
        liquidityLevels[3] = 1_000_000 ether; // 1M ETH
        liquidityLevels[4] = 10_000_000 ether; // 10M ETH

        for (uint256 i = 0; i < liquidityLevels.length; i++) {
            console.log("\n=== Testing with liquidity:", liquidityLevels[i] / 1e18, "ETH ===");
            testLiquidityLevel(amountIn, liquidityLevels[i]);
        }
    }

    function testLiquidityLevel(uint256 amountIn, uint128 liquidity) internal {
        // Calculate base slippage
        uint256 base = mulDiv(amountIn, 2 * TWAP_SLIPPAGE_DENOMINATOR, uint256(liquidity));
        console.log("Base slippage:", base);
        console.log("Base slippage in %:", (base * 100) / TWAP_SLIPPAGE_DENOMINATOR);

        // Show what the final slippage would be
        uint256 finalSlippage = base < MIN_TWAP_SLIPPAGE_TOLERANCE ? MIN_TWAP_SLIPPAGE_TOLERANCE : base;
        console.log("Final slippage:", finalSlippage);
        console.log("Final slippage in %:", (finalSlippage * 100) / TWAP_SLIPPAGE_DENOMINATOR);

        // Show what it would be with a lower minimum
        uint256 lowMinSlippage = 50; // 0.5%
        uint256 finalSlippageLowMin = base < lowMinSlippage ? lowMinSlippage : base;
        console.log("Final slippage with 0.5% min:", finalSlippageLowMin);
        console.log("Final slippage with 0.5% min in %:", (finalSlippageLowMin * 100) / TWAP_SLIPPAGE_DENOMINATOR);
    }
}
