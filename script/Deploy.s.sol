// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "lib/forge-std/src/Script.sol";
import "../src/JBBuybackHook.sol";

contract Deploy is Script {

    function run() public {
        uint256 chainId = block.chainid;
        string memory chain;
        address wethAddress;
        address factoryAddress;

        if (chainId == 1) {
            chain = "1";
            wethAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
            factoryAddress = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
        } else if (chainId == 1337) {
            chain = "1337";
            wethAddress = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
            factoryAddress = 0x0227628f3F023bb0B980b67D528571c95c6DaC1c;
        } else {
            revert("Invalid RPC / no juice contracts deployed on this network");
        }

        address directoryAddress =
            stdJson.readAddress(
            vm.readFile(
                string.concat(
                    "lib/juice-contracts-v4/broadcast/Deploy.s.sol/", chain, "/run-latest.json"
                )
            ),
            ".transactions[2].contractAddress"
        );

        address controllerAddress = (
            stdJson.readAddress(
            vm.readFile(
                string.concat(
                    "lib/juice-contracts-v4/broadcast/Deploy.s.sol/", chain, "/run-latest.json"
                )
            ),
            ".transactions[7].contractAddress"
            )
        );

        vm.broadcast();
        new JBBuybackHook(IWETH9(wethAddress), factoryAddress, IJBDirectory(directoryAddress), IJBController(controllerAddress));
    }
}
