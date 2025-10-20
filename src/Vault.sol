// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MiaoToken} from "./MiaoToken.sol";

contract Vault {

    MiaoToken private s_miaoToken;

    event Vault__Deposit(address indexed user, uint256 indexed amount);
    event Vault__Redeem(address indexed user, uint256 indexed amount);

    error Vault__TransferFail(address user);

    constructor(address miaoTokenAddress) {
        s_miaoToken = MiaoToken(miaoTokenAddress);
    }

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        uint256 amount = msg.value;
        s_miaoToken.mint(msg.sender, amount);
        emit Vault__Deposit(msg.sender, amount);
    }

    function redeem(uint256 amount) external {
        s_miaoToken.burn(msg.sender, amount);
        (bool success,) = payable(msg.sender).call{value: amount}("");
        if (!success) {
            revert Vault__TransferFail(msg.sender);
        }
        emit Vault__Redeem(msg.sender, amount);
    }

}