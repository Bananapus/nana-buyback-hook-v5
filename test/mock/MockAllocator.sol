// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "lib/juice-contracts-v4/src/structs/JBSplitHookPayload.sol";
import "lib/juice-contracts-v4/src/structs/JBTokenAmount.sol";
import "lib/juice-contracts-v4/src/interfaces/IJBPayHook.sol";
import "lib/juice-contracts-v4/src/interfaces/IJBSplitHook.sol";

import "lib/openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";

contract MockAllocator is ERC165, IJBSplitHook {
    IJBPayHook public immutable payDelegate;

    constructor(IJBPayHook _payDelegate) {
        payDelegate = _payDelegate;
    }

    function allocate(JBSplitHookPayload calldata _data) external payable override {
        _data;

        JBDidPayData memory _didPaydata = JBDidPayData(
            address(this),
            1,
            2,
            JBTokenAmount(address(this), 1 ether, 10 ** 18, 0),
            JBTokenAmount(address(this), 1 ether, 10 ** 18, 0),
            1,
            address(this),
            true,
            "",
            new bytes(0)
        );

        // makes a malicious delegate call to the buyback delegate
        (bool success,) =
            address(payDelegate).delegatecall(abi.encodeWithSignature("didPay(JBDidPayData)", _didPaydata));
        assert(success);
    }

    function supportsInterface(bytes4 _interfaceId) public view override(IERC165, ERC165) returns (bool) {
        return _interfaceId == type(IJBSplitHook).interfaceId || super.supportsInterface(_interfaceId);
    }
}
