// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBToken} from "@bananapus/core/src/interfaces/IJBToken.sol";

/// @custom:member token The token to claim the vested buybacks of.
/// @custom:member beneficiary The address which the buybacks belong to.
struct JBVestedBuybackClaims {
    IJBToken token;
    address beneficiary;
}
