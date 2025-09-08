// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vault} from "../../src/Vault.sol";
import {MiaoToken} from "../../src/MiaoToken.sol";
import {Test, console2} from "forge-std/Test.sol";

contract VaultTest is Test {

    MiaoToken private miaoToken;
    Vault private vault;
    address private user = makeAddr("user");

    function setUp() external {
        vm.startBroadcast();
        miaoToken = new MiaoToken();
        vault = new Vault(address(miaoToken));
        miaoToken.grantRole(miaoToken.getMintAndBurnRole(), address(vault));
        vm.stopBroadcast();
    }

    function testDeposit(uint32 amount) public {
        amount = uint32(bound(amount, 1, type(uint32).max));
        vm.deal(user, amount);
        uint256 startingUserBalance = user.balance;
        uint256 startingUserMiaoBalance = miaoToken.principleBalanceOf(user);
        uint256 startingVaultBalance = address(vault).balance;
        vm.prank(user);
        vault.deposit{value: amount}();
        assertEq(user.balance, startingUserBalance - amount);
        assertEq(address(vault).balance, startingVaultBalance + amount);
        assertEq(miaoToken.principleBalanceOf(user), startingUserMiaoBalance + amount);
    }

    function testRedeem(uint256 amount) public {
        amount = uint32(bound(amount, 1, type(uint32).max));
        vm.deal(user, amount);
        vm.startPrank(user);
        vault.deposit{value: amount}();
        uint256 startingUserBalance = user.balance;
        uint256 startingVaultBalance = address(vault).balance;
        uint256 startingTotalSupply = miaoToken.totalSupply();
        vault.redeem(amount);
        assertEq(user.balance, startingUserBalance + amount);
        assertEq(address(vault).balance, startingVaultBalance - amount);
        assertEq(miaoToken.totalSupply(), startingTotalSupply - amount);
    }

    function testReceive(uint256 amount) public {
        amount = uint32(bound(amount, 1, type(uint32).max));
        vm.deal(user, amount);
        uint256 startingUserBalance = user.balance;
        uint256 startingUserMiaoBalance = miaoToken.principleBalanceOf(user);
        uint256 startingVaultBalance = address(vault).balance;
        vm.prank(user);
        payable(address(vault)).call{value: amount}("");
        assertEq(user.balance, startingUserBalance - amount);
        assertEq(address(vault).balance, startingVaultBalance + amount);
        assertEq(miaoToken.principleBalanceOf(user), startingUserMiaoBalance + amount);
    } 

}