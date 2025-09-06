// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IJBRulesetDataHook} from "@bananapus/core/src/interfaces/IJBRulesetDataHook.sol";
import {JBMetadataResolver} from "@bananapus/core/src/libraries/JBMetadataResolver.sol";
import {JBBeforePayRecordedContext} from "@bananapus/core/src/structs/JBBeforePayRecordedContext.sol";
import {JBBeforeCashOutRecordedContext} from "@bananapus/core/src/structs/JBBeforeCashOutRecordedContext.sol";
import {JBCashOutHookSpecification} from "@bananapus/core/src/structs/JBCashOutHookSpecification.sol";
import {JBPayHookSpecification} from "@bananapus/core/src/structs/JBPayHookSpecification.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {JBPermissionIds} from "@bananapus/permission-ids/src/JBPermissionIds.sol";

import {IJBBuybackHookRegistry} from "./interfaces/IJBBuybackHookRegistry.sol";

contract JBBuybackHookRegistry is IJBBuybackHookRegistry, IERC165, Ownable {
    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error JBBuybackHookRegistry_HookLocked(uint256 projectId);
    error JBBuybackHookRegistry_HookNotAllowed(IJBRulesetDataHook hook);
    error JBBuybackHookRegistry_HookNotSet(uint256 projectId);

    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//

    /// @notice The default hook to use.
    IJBRulesetDataHook public override defaultHook;

    /// @notice Whether the hook for the given project is locked.
    /// @custom:param projectId The ID of the project to get the locked hook for.
    mapping(uint256 projectId => bool) public override hasLockedHook;

    /// @notice The hook for the given project.
    /// @custom:param projectId The ID of the project to get the hook for.
    mapping(uint256 projectId => IJBRulesetDataHook) public override hookOf;

    /// @notice The address of each project's token.
    /// @custom:param projectId The ID of the project the token belongs to.
    mapping(IJBRulesetDataHook hook => bool) public override isHookAllowed;

    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//

    /// @param permissions The permissions contract.
    /// @param startingHook The starting hook to use.
    constructor(
        IJBPermissions permissions,
        IJBRulesetDataHook startingHook,
        address owner
    )
        JBPermissioned(permissions)
        Ownable(owner)
    {
        defaultHook = startingHook;
    }

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @notice Forward the call to the hook for the project.
    function beforePayRecordedWith(JBBeforePayRecordedContext calldata context)
        external
        view
        override
        returns (uint256 weight, JBPayHookSpecification[] memory hookSpecifications)
    {
        // Get the hook for the project.
        IJBRulesetDataHook hook = hookOf[context.projectId];

        // If the hook is not set, use the default hook.
        if (hook == IJBRulesetDataHook(0)) hook = defaultHook;

        // Forward the call to the hook.
        return hook.beforePayRecordedWith(context);
    }

    /// @notice To fulfill the `IJBRulesetDataHook` interface.
    /// @dev Pass cash out context back to the terminal without changes.
    /// @param context The cash out context passed in by the terminal.
    function beforeCashOutRecordedWith(JBBeforeCashOutRecordedContext calldata context)
        external
        pure
        override
        returns (uint256, uint256, uint256, JBCashOutHookSpecification[] memory hookSpecifications)
    {
        return (context.cashOutTaxRate, context.cashOutCount, context.totalSupply, hookSpecifications);
    }

    /// @notice Make sure the hook has mint permission.
    function hasMintPermissionFor(uint256, address addr) external pure override returns (bool) {
        // Get the hook for the project.
        IJBRulesetDataHook hook = hookOf[context.projectId];

        // If the hook is not set, use the default hook.
        if (hook == IJBRulesetDataHook(0)) hook = defaultHook;

        // Make sure the hook has mint permission.
        return addr == address(hook);
    }

    //*********************************************************************//
    // -------------------------- public views --------------------------- //
    //*********************************************************************//

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IJBRulesetDataHook).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Allow a hook.
    /// @dev Only the owner can allow a hook.
    /// @param hook The hook to allow.
    function allowHook(IJBRulesetDataHook hook) external onlyOwner {
        // Allow the hook.
        isHookAllowed[hook] = true;

        emit JBBuybackHookRegistry_AllowHook(hook);
    }

    /// @notice Disallow a hook.
    /// @dev Only the owner can disallow a hook.
    /// @param hook The hook to disallow.
    function disallowHook(IJBRulesetDataHook hook) external onlyOwner {
        // Disallow the hook.
        isHookAllowed[hook] = false;

        emit JBBuybackHookRegistry_DisallowHook(hook);
    }

    /// @notice Lock a hook for a project.
    /// @dev Only the project's owner or an address with the `JBPermissionIds.SET_BUYBACK_POOL` permission from the
    /// owner can lock a hook for a project.
    /// @param projectId The ID of the project to lock the hook for.
    function lockHookFor(uint256 projectId) external {
        // Enforce permissions.
        _requirePermissionFrom({
            account: PROJECTS.ownerOf(projectId),
            projectId: projectId,
            permissionId: JBPermissionIds.SET_BUYBACK_POOL
        });

        // Set the hook to locked.
        hasLockedHook[projectId] = true;

        // If the hook is not set, lock in the default hook.
        if (hookOf[projectId] == IJBRulesetDataHook(0)) hookOf[projectId] = defaultHook;

        emit JBBuybackHookRegistry_LockHook(projectId);
    }
    /// @notice Set the default hook.
    /// @dev Only the owner can set the default hook.
    /// @param hook The hook to set as the default.

    function setDefaultHook(IJBRulesetDataHook hook) external onlyOwner {
        // Set the default hook.
        defaultHook = hook;

        // Allow the default hook.
        isHookAllowed[hook] = true;

        emit JBBuybackHookRegistry_SetDefaultHook(hook);
    }

    /// @notice Set the hook for a project.
    /// @dev Only the project's owner or an address with the `JBPermissionIds.SET_BUYBACK_POOL` permission from the
    /// owner can set the hook for a project.
    /// @param projectId The ID of the project to set the hook for.
    /// @param hook The hook to set for the project.
    function setHookFor(uint256 projectId, IJBRulesetDataHook hook) external {
        // Make sure the hook is not locked.
        if (hasLockedHook[projectId]) revert JBBuybackHookRegistry_HookLocked(projectId);

        if (!isHookAllowed[hook]) revert JBBuybackHookRegistry_HookNotAllowed(hook);

        // Enforce permissions.
        _requirePermissionFrom({
            account: PROJECTS.ownerOf(projectId),
            projectId: projectId,
            permissionId: JBPermissionIds.SET_BUYBACK_POOL
        });

        // Set the hook.
        hookOf[projectId] = hook;

        emit JBBuybackHookRegistry_SetHook(projectId, hook);
    }
}
