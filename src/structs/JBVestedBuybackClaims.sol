// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @custom:member projectId The ID of the project which the buybacks apply to.
/// @custom:member beneficiary The address which the buybacks belong to.
struct JBVestedBuybackClaims {
    uint256 projectId;
    address beneficiary;
}
