// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @custom:member amount The amount of tokens to be streamed to the beneficiary.
/// @custom:member startTime The start time of the vesting period.
/// @custom:member endTime The end time of the vesting period.
struct JBVestingBuyback {
    uint256 amount;
    uint256 startTime;
    uint256 endTime;
}
