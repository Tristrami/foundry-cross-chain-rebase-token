// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {MiaoToken} from "../src/MiaoToken.sol";
import {Vault} from "../src/Vault.sol";
import {DevOpsTools} from "@foundry-devops/src/DevOpsTools.sol";

contract DeployVault is Script {

    function run() external {
        address miaoTokenAddress = DevOpsTools.get_most_recent_deployment("MiaoToken", block.chainid);
        deploy(miaoTokenAddress);
    }

    function deploy(address miaoTokenAddress) public returns (Vault) {
        MiaoToken miaoToken = MiaoToken(miaoTokenAddress);
        vm.startBroadcast();
        Vault vault = new Vault(miaoTokenAddress);
        miaoToken.grantRole(miaoToken.getMintAndBurnRole(), address(vault));
        vm.stopBroadcast();
        return vault;
    }
}