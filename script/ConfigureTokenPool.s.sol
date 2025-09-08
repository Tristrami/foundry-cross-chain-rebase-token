// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MiaoToken} from "../src/MiaoToken.sol";
import {MiaoTokenPool} from "../src/MiaoTokenPool.sol";
import {DevOpsTools} from "@foundry-devops/src/DevOpsTools.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "@ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";
import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract ConfigureTokenPool is Script {

    using stdJson for string;

    /// @dev The fields in TokenPool.ChainUpdate are reordered alphabetically for convenient JSON parsing
    /// @notice The data types for remoteTokenAddress and remotePoolAddress are changed from bytes to address for convenient JSON parsing
    struct PoolConfig {
        bool allowed; // Whether the chain should be enabled
        RateLimiterConfig inboundRateLimiterConfig; // Inbound rate limited config, meaning the rate limits for all of the offRamps for the given chain
        RateLimiterConfig outboundRateLimiterConfig; // Outbound rate limited config, meaning the rate limits for all of the onRamps for the given chain
        uint64 remoteChainSelector; // Remote chain selector
        address remotePoolAddress; // Address of the remote pool
        address remoteTokenAddress; // Address of the remote token
    }

    /// @dev The fields in RateLimiter.Config are reordered alphabetically for convenient JSON parsing
    struct RateLimiterConfig {
        uint128 capacity; // Specifies the capacity of the rate limiter
        bool isEnabled; // Indication whether the rate limiting should be enabled
        uint128 rate; // Specifies the rate of the rate limiter
    }

    function run() external {
        address tokenPoolAddress = DevOpsTools.get_most_recent_deployment("MiaoTokenPool", block.chainid);
        configure(MiaoTokenPool(tokenPoolAddress));
    }

    function configure(MiaoTokenPool miaoTokenPool) public {
        console2.log("Configure token pool using poolConfig.json");
        TokenPool.ChainUpdate[] memory chainUpdates = createChainUpdates(parseJsonPoolConfig("config/poolConfig.json"));
        applyChainUpdates(localTokenPoolAddress, chainUpdates);
    }

    function configure(
        address localTokenPoolAddress,
        uint64 remoteChainSelector,
        address remoteTokenAddress,
        bool allowed,
        address remotePoolAddress,
        bool inboundRateLimiterIsEnabled,
        uint128 inboundRateLimiterCapacity,
        uint128 inboundRateLimiterRate,
        bool outboundRateLimiterIsEnabled,
        uint128 outboundRateLimiterCapacity,
        uint128 outboundRateLimiterRate
    ) public {
        console2.log("Start to configure token pool ...");
        PoolConfig memory poolConfig = PoolConfig({
        remoteChainSelector: remoteChainSelector,
            allowed: allowed,
            remotePoolAddress: remotePoolAddress,
            remoteTokenAddress: remoteTokenAddress,
            outboundRateLimiterConfig: RateLimiterConfig({
                isEnabled: outboundRateLimiterIsEnabled,
                capacity: outboundRateLimiterCapacity,
                rate: outboundRateLimiterRate
            }),
            inboundRateLimiterConfig: RateLimiterConfig({
                isEnabled: inboundRateLimiterIsEnabled,
                capacity: inboundRateLimiterCapacity,
                rate: inboundRateLimiterRate
            })
        });
        PoolConfig[] memory poolConfigs = new PoolConfig[](1);
        poolConfigs[0] = poolConfig;
        TokenPool.ChainUpdate[] memory chainUpdates = createChainUpdates(poolConfigs);
        applyChainUpdates(localTokenPoolAddress, chainUpdates);
        console2.log("Token pool configured successfully");
    }

    function applyChainUpdates(address localTokenPoolAddress, TokenPool.ChainUpdate[] memory chainUpdates) private {
        vm.startBroadcast();
        MiaoTokenPool(localTokenPoolAddress).applyChainUpdates(chainUpdates);
        vm.stopBroadcast();
    }

    function configure(
        address localTokenPoolAddress,
        uint64 remoteChainSelector,
        address remoteTokenAddress,
        bool allowed,
        address remotePoolAddress
    ) public {
        configure(
            localTokenPoolAddress,
            remoteChainSelector,
            remoteTokenAddress,
            allowed,
            remotePoolAddress,
            false,
            0,
            0,
            false,
            0,
            0
        );
    }

    function createChainUpdates(PoolConfig[] memory poolConfigs) private pure returns (TokenPool.ChainUpdate[] memory) {
        TokenPool.ChainUpdate[] memory chainUpdates = new TokenPool.ChainUpdate[](poolConfigs.length);
        for (uint256 i = 0; i < poolConfigs.length; i++) {
            PoolConfig memory c = poolConfigs[i];
            TokenPool.ChainUpdate memory chainUpdate = TokenPool.ChainUpdate({
                remoteChainSelector: c.remoteChainSelector,
                allowed: c.allowed,
                remotePoolAddress: abi.encode(c.remotePoolAddress),
                remoteTokenAddress: abi.encode(c.remoteTokenAddress),
                outboundRateLimiterConfig: RateLimiter.Config({
                    isEnabled: c.outboundRateLimiterConfig.isEnabled,
                    capacity: c.outboundRateLimiterConfig.capacity,
                    rate: c.outboundRateLimiterConfig.rate
                }),
                inboundRateLimiterConfig: RateLimiter.Config({
                    isEnabled: c.inboundRateLimiterConfig.isEnabled,
                    capacity: c.inboundRateLimiterConfig.capacity,
                    rate: c.inboundRateLimiterConfig.rate
                })
            });
            chainUpdates[i] = chainUpdate;
        }
        return chainUpdates;
    }

    function parseJsonPoolConfig(string memory jsonFilePath) private view returns (PoolConfig[] memory) {
        string memory poolConfigJson = vm.readFile(jsonFilePath);
        string memory key = string.concat(".", vm.toString(block.chainid));
        bytes memory poolConfigArrBytes = poolConfigJson.parseRaw(key);
        return abi.decode(poolConfigArrBytes, (PoolConfig[]));
    }
}