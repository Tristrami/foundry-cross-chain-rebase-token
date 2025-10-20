// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {MiaoToken} from "../../src/MiaoToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

// 1. Change some tests to fuzz tests
// 2. Use vm.expectPartialRevert to test using only error selector to match the reverted error with parameters
contract MiaoTokenTest is Test {

    uint256 private constant PRECISION_FACTOR = 1e18;
    MiaoToken private miaoToken;
    address private user = makeAddr("user");

    function setUp() external {
        vm.startBroadcast();
        miaoToken = new MiaoToken();
        vm.stopBroadcast();
    }

    function test_OwnerHasOwnerRoleAndTokenAdminRole() public view {
        assert(miaoToken.hasRole(miaoToken.getOwnerRole(), miaoToken.getOwner()));
        assert(miaoToken.hasRole(miaoToken.getMintAndBurnRole(), miaoToken.getOwner()));
    }

    function test_RevertWhen_RandomUserUpdateInterestRate() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        miaoToken.setGlobalInterestRate(1e5);
    }

    function test_OwnerCanUpdateInterestRate() public {
        uint256 newInterestRate = 1e5;
        address owner = miaoToken.getOwner();
        vm.prank(owner);
        miaoToken.setGlobalInterestRate(newInterestRate);
        assertEq(miaoToken.getGlobalInterestRate(), newInterestRate);
    }

    function test_RevertWhen_RandomUserMintAndBurnToken() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, miaoToken.getMintAndBurnRole()));
        miaoToken.mint(user, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, miaoToken.getMintAndBurnRole()));
        miaoToken.burn(user, 1 ether);
    }

    function test_OwnerCanMintAndBurnToken() public {
        address owner = miaoToken.getOwner();
        uint256 startingUserBalance = miaoToken.principleBalanceOf(user);
        uint256 amountToMint = 1 ether;
        vm.startPrank(owner);
        miaoToken.mint(user, amountToMint);
        assertEq(miaoToken.principleBalanceOf(user), startingUserBalance + amountToMint);
        miaoToken.burn(user, amountToMint);
        assertEq(miaoToken.principleBalanceOf(user), startingUserBalance);
    }

    function test_TokenAdminCanMintAndBurnToken() public {
        address owner = miaoToken.getOwner();
        address admin = makeAddr("admin");
        uint256 startingUserBalance = miaoToken.principleBalanceOf(user);
        uint256 amountToMint = 1 ether;
        vm.startPrank(owner);
        miaoToken.grantRole(miaoToken.getMintAndBurnRole(), admin);
        vm.stopPrank();
        vm.startPrank(admin);
        miaoToken.mint(user, amountToMint);
        assertEq(miaoToken.principleBalanceOf(user), startingUserBalance + amountToMint);
        miaoToken.burn(user, amountToMint);
        assertEq(miaoToken.principleBalanceOf(user), startingUserBalance);
    }

    function test_UserInterestRateIsCurrentGlobalInterestRate() public {
        address owner = miaoToken.getOwner();
        uint256 globalInterestRate = miaoToken.getGlobalInterestRate();
        uint256 newInterestRate = 1e5;
        vm.startPrank(owner);
        miaoToken.mint(user, 1 ether);
        assertEq(miaoToken.getUserInterestRate(user), globalInterestRate);
        miaoToken.setGlobalInterestRate(newInterestRate);
        miaoToken.mint(user, 1 ether);
        assertEq(miaoToken.getGlobalInterestRate(), newInterestRate);
        assertEq(miaoToken.getUserInterestRate(user), newInterestRate);
    }

    function test_MintTransfersAccruedInterestAndUpdateUserInterestRate() public {
        address owner = miaoToken.getOwner();
        uint256 amountToMint = 1 ether;
        uint256 startingTimestamp = block.timestamp;
        vm.startPrank(owner);
        miaoToken.mint(user, amountToMint);
        uint256 startingUserPrincipleBalance = miaoToken.principleBalanceOf(user);
        uint256 startingTotalSupply = miaoToken.totalSupply();
        uint256 interestRate = miaoToken.getUserInterestRate(user);
        uint256 timeElapsed = 2 seconds;
        uint256 expectedAccruedInterest = startingUserPrincipleBalance * interestRate * timeElapsed / PRECISION_FACTOR;
        uint256 newInterestRate = 1e5;
        miaoToken.setGlobalInterestRate(newInterestRate);
        vm.warp(startingTimestamp + timeElapsed);
        miaoToken.mint(user, amountToMint);
        uint256 endingUserPrincipleBalance = miaoToken.principleBalanceOf(user);
        assertEq(endingUserPrincipleBalance, startingUserPrincipleBalance + amountToMint + expectedAccruedInterest);
        assertEq(miaoToken.getUserInterestRate(user), newInterestRate);
        assertEq(miaoToken.totalSupply(), startingTotalSupply + amountToMint + expectedAccruedInterest);
    }

    function test_RevertWhen_AmountToBurnExceedsBalance() public {
        address owner = miaoToken.getOwner();
        uint256 amountToMint = 1 ether;
        uint256 amountToBurn = 2 ether;
        vm.startPrank(owner);
        miaoToken.mint(user, amountToMint);
        uint256 balance = miaoToken.balanceOf(user);
        vm.expectRevert(abi.encodeWithSelector(MiaoToken.MiaoToken__AmountToBurnExceedsBalance.selector, amountToBurn, balance));
        miaoToken.burn(user, amountToBurn);
    }

    function test_BurnAllTokens() public {
        address owner = miaoToken.getOwner();
        uint256 amountToMint = 1 ether;
        vm.startPrank(owner);
        miaoToken.mint(user, amountToMint);
        vm.warp(block.timestamp + 2);
        miaoToken.burn(user, type(uint256).max);
        assertEq(miaoToken.balanceOf(user), 0);
    }

    function test_TransferAllTokens() public {
        address receiver = makeAddr("receiver");
        address owner = miaoToken.getOwner();
        uint256 initialBalance = 1 ether;
        uint256 startingTimestamp = block.timestamp;
        uint256 interestRate = miaoToken.getGlobalInterestRate();
        uint256 timeElapsed = 2 seconds;
        uint256 expectedAccruedInterest = initialBalance * interestRate * timeElapsed / PRECISION_FACTOR;
        // Mint tokens to sender and receiver
        vm.startPrank(owner);
        miaoToken.mint(user, initialBalance);
        miaoToken.mint(receiver, initialBalance);
        vm.stopPrank();
        // Transfer all tokens to receiver after 2 seconds
        vm.warp(startingTimestamp + timeElapsed);
        vm.prank(user);
        miaoToken.transfer(receiver, type(uint256).max);
        // Check balance
        uint256 endingReceiverPrincipleBalance = miaoToken.principleBalanceOf(receiver);
        // The final principle balance of receiver should be the sum of 
        // user's (initialBalance + interest) and the receiver's own (initialBalance + interest)
        uint256 expectedReceiverBalance = (initialBalance + expectedAccruedInterest) * 2;
        assertEq(endingReceiverPrincipleBalance, expectedReceiverBalance);
    }

    function test_RevertWhen_TransferFromAllTokensWithDelayAfterApprove() public {
        // This test assumes that the spender will call transferFrom function to transfer 
        // all sender's tokens a few seconds after the sender calls approve function.
        // This test is expected to revert an InsufficientAllowance error
        uint256 initialBalance = 1 ether;
        address owner = miaoToken.getOwner();
        address sender = makeAddr("sender");
        address receiver = makeAddr("receiver");
        uint256 timeElapsed = 2 seconds;
        // Mint some tokens to sender
        vm.prank(owner);
        miaoToken.mint(sender, initialBalance);
        // Approve user to spend all of the balance at the moment
        vm.startPrank(sender);
        uint256 balance = miaoToken.balanceOf(sender);
        miaoToken.approve(user, balance);
        vm.stopPrank();
        // Transfer all tokens after 2 seconds
        vm.warp(block.timestamp + timeElapsed);
        uint256 balanceWithInterest = miaoToken.balanceOf(sender);
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, user, balance, balanceWithInterest));
        miaoToken.transferFrom(sender, receiver, type(uint256).max);
    }

    function test_TransferFromTheSameAmountAsApproved() public {
        uint256 initialBalance = 1 ether;
        uint256 timeElapsed = 2 seconds;
        uint256 interestRate = miaoToken.getGlobalInterestRate();
        address owner = miaoToken.getOwner();
        address sender = makeAddr("sender");
        address receiver = makeAddr("receiver");
        uint256 expectedAccruedInterest = initialBalance * interestRate * timeElapsed / PRECISION_FACTOR;
        // Mint some tokens to sender
        vm.prank(owner);
        miaoToken.mint(sender, initialBalance);
        // Approve user to spend all of the balance at the moment
        vm.startPrank(sender);
        uint256 approvedAmount = miaoToken.balanceOf(sender);
        miaoToken.approve(user, approvedAmount);
        vm.stopPrank();
        // Transfer approved amount of tokens after 2 seconds
        vm.warp(block.timestamp + timeElapsed);
        vm.startPrank(user);
        miaoToken.transferFrom(sender, receiver, approvedAmount);
        // Check balance
        assertEq(miaoToken.balanceOf(sender), initialBalance + expectedAccruedInterest - approvedAmount);
        assertEq(miaoToken.balanceOf(receiver), approvedAmount);
    }

}