// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vault} from "../src/Vault.sol";
import {DevOpsTools} from "@foundry-devops/src/DevOpsTools.sol";
import {Script} from "forge-std/Script.sol";

contract Deposit is Script {

    uint256 private constant DEPOSIT_AMOUNT = 1 ether;

    function run() external {
        
        deposit(DEPOSIT_AMOUNT);
    }

    function deposit(uint256 amount) public {
        address vaultAddress = DevOpsTools.get_most_recent_deployment("Vault", block.chainid);
        deposit(vaultAddress, amount);
    }

    function deposit(address vaultAddress, uint256 amount) public {
        vm.startBroadcast();
        Vault(payable(vaultAddress)).deposit{value: amount}();
        vm.stopBroadcast();
    }
}

contract Redeem is Script {

    uint256 private constant REDEEM_AMOUNT = 1 ether;

    function run() external {
        redeem(REDEEM_AMOUNT);
    }

    function redeem(uint256 amount) public {
        address vaultAddress = DevOpsTools.get_most_recent_deployment("Vault", block.chainid);
        redeem(vaultAddress, amount);
    }

    function redeem(address vaultAddress, uint256 amount) public {
        vm.startBroadcast();
        Vault(payable(vaultAddress)).redeem(amount);
        vm.stopBroadcast();
    }
}