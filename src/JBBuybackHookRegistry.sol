// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {JBPermissioned} from "@bananapus/core-v5/src/abstract/JBPermissioned.sol";
import {IJBPermissions} from "@bananapus/core-v5/src/interfaces/IJBPermissions.sol";
import {IJBProjects} from "@bananapus/core-v5/src/interfaces/IJBProjects.sol";
import {IJBRulesetDataHook} from "@bananapus/core-v5/src/interfaces/IJBRulesetDataHook.sol";
import {JBMetadataResolver} from "@bananapus/core-v5/src/libraries/JBMetadataResolver.sol";
import {JBBeforePayRecordedContext} from "@bananapus/core-v5/src/structs/JBBeforePayRecordedContext.sol";
import {JBBeforeCashOutRecordedContext} from "@bananapus/core-v5/src/structs/JBBeforeCashOutRecordedContext.sol";
import {JBCashOutHookSpecification} from "@bananapus/core-v5/src/structs/JBCashOutHookSpecification.sol";
import {JBPayHookSpecification} from "@bananapus/core-v5/src/structs/JBPayHookSpecification.sol";
import {JBRuleset} from "@bananapus/core-v5/src/structs/JBRuleset.sol";
import {JBPermissionIds} from "@bananapus/permission-ids-v5/src/JBPermissionIds.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";

import {IJBBuybackHookRegistry} from "./interfaces/IJBBuybackHookRegistry.sol";

contract JBBuybackHookRegistry is IJBBuybackHookRegistry, ERC2771Context, JBPermissioned, Ownable {
    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error JBBuybackHookRegistry_HookLocked(uint256 projectId);
    error JBBuybackHookRegistry_HookNotAllowed(IJBRulesetDataHook hook);
    error JBBuybackHookRegistry_HookNotSet(uint256 projectId);

    //*********************************************************************//
    // -------------------- public immutable properties ------------------ //
    //*********************************************************************//

    /// @notice The project registry.
    IJBProjects public immutable override PROJECTS;

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
    /// @param projects The project registry.
    /// @param owner The owner of the contract.
    /// @param trustedForwarder A trusted forwarder of transactions to this contract.
    constructor(
        IJBPermissions permissions,
        IJBProjects projects,
        address owner,
        address trustedForwarder
    )
        JBPermissioned(permissions)
        ERC2771Context(trustedForwarder)
        Ownable(owner)
    {
        PROJECTS = projects;
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
        if (hook == IJBRulesetDataHook(address(0))) hook = defaultHook;

        // Forward the call to the hook.
        // slither-disable-next-line unused-return
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
    /// @param projectId The ID of the project to check the mint permission for.
    /// @param addr The address to check the mint permission for.
    /// @return Whether the address has mint permission.
    function hasMintPermissionFor(
        uint256 projectId,
        JBRuleset memory,
        address addr
    )
        external
        view
        override
        returns (bool)
    {
        // Get the hook for the project.
        IJBRulesetDataHook hook = hookOf[projectId];

        // If the hook is not set, use the default hook.
        if (hook == IJBRulesetDataHook(address(0))) hook = defaultHook;

        // Make sure the hook has mint permission.
        return addr == address(hook);
    }

    //*********************************************************************//
    // -------------------------- public views --------------------------- //
    //*********************************************************************//

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IJBBuybackHookRegistry).interfaceId
            || interfaceId == type(IJBRulesetDataHook).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    //*********************************************************************//
    // -------------------------- internal views ------------------------- //
    //*********************************************************************//

    /// @dev `ERC-2771` specifies the context as being a single address (20 bytes).
    function _contextSuffixLength() internal view override(ERC2771Context, Context) returns (uint256) {
        return super._contextSuffixLength();
    }

    /// @notice The calldata. Preferred to use over `msg.data`.
    /// @return calldata The `msg.data` of this call.
    function _msgData() internal view override(ERC2771Context, Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }

    /// @notice The message's sender. Preferred to use over `msg.sender`.
    /// @return sender The address which sent this call.
    function _msgSender() internal view override(ERC2771Context, Context) returns (address sender) {
        return ERC2771Context._msgSender();
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
        if (hookOf[projectId] == IJBRulesetDataHook(address(0))) hookOf[projectId] = defaultHook;

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
