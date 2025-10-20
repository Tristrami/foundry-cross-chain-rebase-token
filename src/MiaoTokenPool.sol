// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MiaoToken} from "./MiaoToken.sol";
import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {Pool} from "@ccip/contracts/src/v0.8/ccip/libraries/Pool.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

contract MiaoTokenPool is TokenPool {

    MiaoToken private s_miaoToken;

    constructor(
        MiaoToken miaoToken,
        address[] memory allowList,
        address rmnProxy,
        address router
    ) TokenPool (
        IERC20(address(miaoToken)),
        allowList,
        rmnProxy,
        router
    ) {
        s_miaoToken = miaoToken;
    }

    function lockOrBurn(
        Pool.LockOrBurnInV1 calldata lockOrBurnIn
    ) external override returns (Pool.LockOrBurnOutV1 memory lockOrBurnOut) {
        _validateLockOrBurn(lockOrBurnIn);
        s_miaoToken.burn(address(this), lockOrBurnIn.amount);
        lockOrBurnOut = Pool.LockOrBurnOutV1({
            destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
            destPoolData: abi.encode(s_miaoToken.getUserInterestRate(lockOrBurnIn.originalSender))
        });
        return lockOrBurnOut;
    }

    function releaseOrMint(
        Pool.ReleaseOrMintInV1 calldata releaseOrMintIn
    ) external override returns (Pool.ReleaseOrMintOutV1 memory) {
        _validateReleaseOrMint(releaseOrMintIn);
        address receiver = releaseOrMintIn.receiver;
        uint256 interestRate = abi.decode(releaseOrMintIn.sourcePoolData, (uint256));
        s_miaoToken.mint(receiver, releaseOrMintIn.amount, interestRate);
        return Pool.ReleaseOrMintOutV1({
            destinationAmount: releaseOrMintIn.amount
        });
    }
}