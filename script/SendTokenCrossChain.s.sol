// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MiaoToken} from "../src/MiaoToken.sol";
import {MiaoTokenPool} from "../src/MiaoTokenPool.sol";
import {DevOpsTools} from "@foundry-devops/src/DevOpsTools.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {Script, console2} from "forge-std/Script.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";

contract SendTokenCrossChain is Script {

    error SendTokenCrossChain__SenderIsNotInProtocol(address sender);

    function send(address receiver, uint256 amount, uint64 destinationChainSelector) public returns (bytes32) {
        address miaoTokenAddress = DevOpsTools.get_most_recent_deployment("MiaoToken", block.chainid);
        CCIPLocalSimulatorFork ccip = new CCIPLocalSimulatorFork();
        Register.NetworkDetails memory networkDetails = ccip.getNetworkDetails(block.chainid);
        return send(
            miaoTokenAddress,
            networkDetails.linkAddress,
            networkDetails.routerAddress,
            destinationChainSelector,
            receiver,
            amount
        );
    }

    function send(
        address localMiaoTokenAddress,
        address linkTokenAddress,
        address routerAddress,
        uint64 destinationChainSelector,
        address receiver,
        uint256 amount
    ) public returns (bytes32) {
        console2.log("Start to send token cross chain ...");
        console2.log("Sender:", vm.toString(msg.sender));
        console2.log("Receiver:", vm.toString(receiver));
        console2.log("Amount:", amount);
         // Create ccip message
        Client.EVM2AnyMessage memory message = createCCIPMessage(
            localMiaoTokenAddress,
            linkTokenAddress,
            receiver,
            amount
        );
        // Use router client to get fee and send ccip message
        IRouterClient routerClient = IRouterClient(routerAddress);
        uint256 fee = routerClient.getFee(destinationChainSelector, message);
        vm.startBroadcast();
        // Approve router to spend link token and miao token
        IERC20(linkTokenAddress).approve(routerAddress, fee);
        MiaoToken(localMiaoTokenAddress).approve(routerAddress, amount);
        bytes32 messageId = IRouterClient(routerAddress).ccipSend(destinationChainSelector, message);
        vm.stopBroadcast();
        console2.log("Token was sent successfully, message id:", vm.toString(messageId));
        return messageId;
    }

    function createCCIPMessage(
        address localMiaoTokenAddress,
        address linkTokenAddress,
        address receiver,
        uint256 amount
    ) public pure returns (Client.EVM2AnyMessage memory) {
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: localMiaoTokenAddress,
            amount: amount
        });
        return Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: "",
            feeToken: linkTokenAddress,
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV2({
                gasLimit: 0,
                allowOutOfOrderExecution: false
            }))
        });
    }

}