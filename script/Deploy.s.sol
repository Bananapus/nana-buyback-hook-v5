// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@bananapus/core/script/helpers/CoreDeploymentLib.sol";

import {Sphinx} from "@sphinx-labs/contracts/SphinxPlugin.sol";
import {Script} from "forge-std/Script.sol";

import {JBBuybackHook} from "src/JBBuybackHook.sol";
import {IWETH9} from "src/interfaces/external/IWETH9.sol";

contract DeployScript is Script, Sphinx {
    /// @notice tracks the deployment of the core contracts for the chain we are deploying to.
    CoreDeployment core;

    /// @notice tracks the addresses that are required for the chain we are deploying to.
    address weth;
    address factory;

    function configureSphinx() public override {
        // TODO: Update to contain revnet devs.
        sphinxConfig.owners = [0x26416423d530b1931A2a7a6b7D435Fac65eED27d];
        sphinxConfig.orgId = "cltepuu9u0003j58rjtbd0hvu";
        sphinxConfig.projectName = "nana-buyback-hook";
        sphinxConfig.threshold = 1;
        sphinxConfig.mainnets = ["ethereum", "optimism", "polygon"];
        sphinxConfig.testnets = ["ethereum_sepolia", "optimism_sepolia", "polygon_mumbai"];
        sphinxConfig.saltNonce = 7;
    }

    function run() public {
        // Get the deployment addresses for the nana CORE for this chain.
        // We want to do this outside of the `sphinx` modifier.
        core = CoreDeploymentLib.getDeployment(
            vm.envOr("NANA_CORE_DEPLOYMENT_PATH", string("node_modules/@bananapus/core/deployments/"))
        );

        uint256 chainId = block.chainid;

         // Ethereum Mainnet
        if (chainId == 1) {
            weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
            factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
            // Ethereum Sepolia
        } else if (chainId == 11_155_111) {
            weth = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
            factory = 0x0227628f3F023bb0B980b67D528571c95c6DaC1c;
            // Optimism Mainnet
        } else if (chainId == 420) {
            weth = 0x4200000000000000000000000000000000000006;
            factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
            // Optimism Sepolia
        } else if (chainId == 11_155_420) {
            weth = 0x4200000000000000000000000000000000000006;
            factory = address(0);
            // Polygon Mainnet
        } else if (chainId == 137) {
            weth = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
            factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
            // Polygon Mumbai
        } else if (chainId == 80_001) {
            weth = 0xA6FA4fB5f76172d178d61B04b0ecd319C5d1C0aa;
            factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
        } else {
            revert("Invalid RPC / no juice contracts deployed on this network");
        }

        // Perform the deployment transactions.
        deploy();
    }

    function deploy() public sphinx {
        // TODO: Determine if we want create or create2 here. 
        // Since the args are different, create2 will deploy to different addresses,
        // unless we fetch the weth address in the constructor.
        new JBBuybackHook(
            IWETH9(weth), factory, core.directory, core.controller
        );
    }
}
