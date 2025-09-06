// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBPayHook} from "@bananapus/core/src/interfaces/IJBPayHook.sol";
import {IJBRulesetDataHook} from "@bananapus/core/src/interfaces/IJBRulesetDataHook.sol";

interface IJBBuybackHookRegistry is IJBPayHook, IJBRulesetDataHook {
    event AllowHook(IJBRulesetDataHook hook);
    event DisallowHook(IJBRulesetDataHook hook);
    event SetDefaultHook(IJBRulesetDataHook hook);
    event SetHook(uint256 indexed projectId, IJBRulesetDataHook hook);

    function defaultHook() external view returns (IJBRulesetDataHook);
    function hasLockedHook(uint256 projectId) external view returns (bool);
    function hookOf(uint256 projectId) external view returns (IJBRulesetDataHook);
    function isHookAllowed(IJBRulesetDataHook hook) external view returns (bool);

    function allowHook(IJBRulesetDataHook hook) external;
    function disallowHook(IJBRulesetDataHook hook) external;
    function lockHook(uint256 projectId) external;
    function setDefaultHook(IJBRulesetDataHook hook) external;
    function setHook(uint256 projectId, IJBRulesetDataHook hook) external;
}
