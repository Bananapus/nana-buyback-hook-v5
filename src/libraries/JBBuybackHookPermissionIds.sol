// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Permission IDs for `JBPermissions`. These grant permissions scoped to the `JBBuybackHook`.
library JBBuybackHookPermissionIds {
    // 1-20 - `JBPermissionIds`
    // 21 - `JBHandlePermissionIds`
    // 22-24 - `JB721PermissionIds`

    uint256 public constant SET_POOL_PARAMS = 25;
    uint256 public constant CHANGE_POOL = 26;
}
