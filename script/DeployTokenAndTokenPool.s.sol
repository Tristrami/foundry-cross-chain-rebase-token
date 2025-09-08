// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MiaoToken} from "../src/MiaoToken.sol";
import {MiaoTokenPool} from "../src/MiaoTokenPool.sol";
import {ConfigureTokenPool} from "./ConfigureTokenPool.s.sol";
import {DevOpsTools} from "@foundry-devops/src/DevOpsTools.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "@ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";
import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract DeployTokenAndTokenPool is Script {

    function run() external {
        CCIPLocalSimulatorFork ccip = new CCIPLocalSimulatorFork();
        Register.NetworkDetails memory networkDetails = ccip.getNetworkDetails(block.chainid);
        deploy(
            networkDetails.rmnProxyAddress, 
            networkDetails.routerAddress,
            networkDetails.registryModuleOwnerCustomAddress,
            networkDetails.tokenAdminRegistryAddress
        );
    }

    function deploy(
        address rmnProxyAddress, 
        address routerAddress,
        address registryModuleOwnerCustomAddress,
        address tokenAdminRegistryAddress
    ) public returns (MiaoTokenPool, MiaoToken) {
        console2.log("Start to deploy miao token and token pool on chain", block.chainid);
        MiaoToken miaoToken = deployMiaoToken();
        MiaoTokenPool tokenPool = deployTokenPool(
            miaoToken, 
            rmnProxyAddress, 
            routerAddress,
            registryModuleOwnerCustomAddress,
            tokenAdminRegistryAddress
        );
        console2.log(string.concat("Miao token: ", vm.toString(address(miaoToken)), ", owner: ",  vm.toString(miaoToken.owner())));
        console2.log(string.concat("Miao token pool: ", vm.toString(address(tokenPool)), ", owner: ",  vm.toString(tokenPool.owner())));
        return (tokenPool, miaoToken);
    }

    function deployMiaoToken() private returns (MiaoToken) {
        vm.startBroadcast();
        MiaoToken miaoToken = new MiaoToken();
        vm.stopBroadcast();
        return miaoToken;
    }

    function deployTokenPool(
        MiaoToken miaoToken, 
        address rmnProxyAddress, 
        address routerAddress,
        address registryModuleOwnerCustomAddress,
        address tokenAdminRegistryAddress
    ) private returns (MiaoTokenPool) {
        vm.startBroadcast();
        // Deploy token pool
        MiaoTokenPool tokenPool = new MiaoTokenPool(
            MiaoToken(address(miaoToken)), 
            new address[](0), 
            rmnProxyAddress, 
            routerAddress
        );
        // Grant burn and mint role to token pool
        miaoToken.grantRole(miaoToken.getMintAndBurnRole(), address(tokenPool));
        // Set token pool admin to the token owner
        RegistryModuleOwnerCustom(registryModuleOwnerCustomAddress).registerAdminViaOwner(address(miaoToken));
        // Complete the registration process
        TokenAdminRegistry tokenAdminRegistry = TokenAdminRegistry(tokenAdminRegistryAddress);
        TokenAdminRegistry(tokenAdminRegistryAddress).acceptAdminRole(address(miaoToken));
        // Link token to the pool
        tokenAdminRegistry.setPool(address(miaoToken), address(tokenPool));
        vm.stopBroadcast();
        return tokenPool;
    }
}