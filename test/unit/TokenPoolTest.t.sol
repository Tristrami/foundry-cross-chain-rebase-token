// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {MiaoToken} from "../../src/MiaoToken.sol";
import {MiaoTokenPool} from "../../src/MiaoTokenPool.sol";
import {Vault} from "../../src/Vault.sol";
import {DevOpsTools} from "@foundry-devops/src/DevOpsTools.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "@ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {DeployTokenAndTokenPool} from "../../script/DeployTokenAndTokenPool.s.sol";
import {ConfigureTokenPool} from "../../script/ConfigureTokenPool.s.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SendTokenCrossChain} from "../../script/SendTokenCrossChain.s.sol";
import {DeployVault} from "../../script/DeployVault.s.sol";

contract TokenPoolTest is Test {

    uint256 private constant SEND_AMOUNT = 1e5;
    uint256 private constant INITIAL_LINK_BALANCE = 1 ether;
    uint256 private ethSepoliaAnvilForkId;
    uint256 private arbSepoliaAnvilForkId;
    CCIPLocalSimulatorFork private ccipLocalSimulatorFork;
    Register.NetworkDetails private ethSepoliaNetworkDetails;
    Register.NetworkDetails private arbSepoliaNetworkDetails;
    MiaoTokenPool private ethMiaoTokenPool;
    MiaoTokenPool private arbMiaoTokenPool;
    MiaoToken private ethMiaoToken;
    MiaoToken private arbMiaoToken;
    Vault private ethVault;
    Vault private arbVault;
    address ethUser = makeAddr("ethUser");
    address arbUser = makeAddr("arbUser");

    function setUp() external {
        // Create fork
        ethSepoliaAnvilForkId = vm.createFork("eth");
        arbSepoliaAnvilForkId = vm.createFork("arb");
        // Create deployer and configurator
        DeployTokenAndTokenPool deployer = new DeployTokenAndTokenPool();
        ConfigureTokenPool configureTokenPool = new ConfigureTokenPool();
        // Create and persist CCIPLocalSimulatorFork
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));
        // Switch to arb sepolia
        vm.selectFork(arbSepoliaAnvilForkId);
        // Save network details
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        // Deploy token and token pool
        (arbMiaoTokenPool, arbMiaoToken) = deployer.deploy(
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress,
            arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress,
            arbSepoliaNetworkDetails.tokenAdminRegistryAddress
        );
        // Create vault
        DeployVault arbVaultDeployer = new DeployVault();
        arbVault = arbVaultDeployer.deploy(address(arbMiaoToken));
        // Deposit
        vm.deal(arbUser, SEND_AMOUNT);
        vm.prank(arbUser);
        arbVault.deposit{value: SEND_AMOUNT}();
        // Request some link
        ccipLocalSimulatorFork.requestLinkFromFaucet(arbUser, INITIAL_LINK_BALANCE);
        // Switch to eth sepolia
        vm.selectFork(ethSepoliaAnvilForkId);
        // Save network details
        ethSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        // Deploy token and token pool
        (ethMiaoTokenPool, ethMiaoToken) = deployer.deploy(
            ethSepoliaNetworkDetails.rmnProxyAddress, 
            ethSepoliaNetworkDetails.routerAddress,
            ethSepoliaNetworkDetails.registryModuleOwnerCustomAddress,
            ethSepoliaNetworkDetails.tokenAdminRegistryAddress
        );
        // Create vault
        DeployVault ethVaultDeployer = new DeployVault();
        ethVault = ethVaultDeployer.deploy(address(ethMiaoToken));
        // Deposit
        vm.deal(ethUser, SEND_AMOUNT);
        vm.prank(ethUser);
        ethVault.deposit{value: SEND_AMOUNT}();
        // Request some link
        ccipLocalSimulatorFork.requestLinkFromFaucet(ethUser, INITIAL_LINK_BALANCE);
        // Configure arb sepolia token pool
        vm.selectFork(arbSepoliaAnvilForkId);
        configureTokenPool.configure(
            address(arbMiaoTokenPool),
            ethSepoliaNetworkDetails.chainSelector,
            address(ethMiaoToken),
            true,
            address(ethMiaoTokenPool)
        );
        // Configure eth sepolia token pool
        vm.selectFork(ethSepoliaAnvilForkId);
        configureTokenPool.configure(
            address(ethMiaoTokenPool),
            arbSepoliaNetworkDetails.chainSelector,
            address(arbMiaoToken),
            true,
            address(arbMiaoTokenPool)
        );
    }

    function testSendCrossChainToken() public {
        // Starting balance
        address user = msg.sender;
        vm.selectFork(arbSepoliaAnvilForkId);
        uint256 startingArbUserBalance = arbMiaoToken.principleBalanceOf(user);
        vm.selectFork(ethSepoliaAnvilForkId);
        vm.deal(user, SEND_AMOUNT);
        vm.prank(user);
        ethVault.deposit{value: SEND_AMOUNT}();
        // Request some link
        ccipLocalSimulatorFork.requestLinkFromFaucet(user, INITIAL_LINK_BALANCE);
        uint256 startingEthUserBalance = ethMiaoToken.principleBalanceOf(ethUser);
        uint256 senderInterestRate = ethMiaoToken.getUserInterestRate(ethUser);
        // Send token
        SendTokenCrossChain tokenSender = new SendTokenCrossChain();
        tokenSender.send(
            address(ethMiaoToken),
            ethSepoliaNetworkDetails.linkAddress,
            ethSepoliaNetworkDetails.routerAddress,
            arbSepoliaNetworkDetails.chainSelector,
            user,
            SEND_AMOUNT
        );
        // Switch to arb sepolia and forward the message, do not use vm.selectFork to switch chain before this
        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaAnvilForkId);
        // Change arbMiaoToken's global interest rate
        vm.prank(arbMiaoToken.owner());
        arbMiaoToken.setGlobalInterestRate(2e5);
        // Check receiver's balance and interest rate
        assertEq(arbMiaoToken.principleBalanceOf(user), startingArbUserBalance + SEND_AMOUNT);
        assertEq(arbMiaoToken.getUserInterestRate(user), senderInterestRate);
    }
}