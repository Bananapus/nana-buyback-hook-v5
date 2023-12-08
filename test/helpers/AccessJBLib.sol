// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@juicebox/libraries/JBCurrencies.sol";
import "@juicebox/libraries/JBConstants.sol";
import "@juicebox/libraries/JBConstants.sol";

contract AccessJBLib {
    function ETH() external pure returns (uint256) {
        return JBCurrencies.ETH;
    }

    function USD() external pure returns (uint256) {
        return JBCurrencies.USD;
    }

    function ETHToken() external pure returns (address) {
        return JBConstants.NATIVE_TOKEN;
    }

    function MAX_FEE() external pure returns (uint256) {
        return JBConstants.MAX_FEE;
    }

    function SPLITS_TOTAL_PERCENT() external pure returns (uint256) {
        return JBConstants.SPLITS_TOTAL_PERCENT;
    }
}
