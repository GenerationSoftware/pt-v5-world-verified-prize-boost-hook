// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import { Test, stdError, Vm } from "../lib/forge-std/src/Test.sol";

import { WorldVerifiedPrizeBoostHook, IERC20 } from "../src/WorldVerifiedPrizeBoostHook.sol";
import { ERC20Mock } from "../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import { MockWorldIdAddressBook, IWorldIdAddressBook } from "./contracts/MockWorldIdAddressBook.sol";

contract WorldVerifiedPrizeBoostHookTest is Test {
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event VerifiedPrizeBoosted(address indexed winner, address indexed recipient, address indexed vault, uint256 prizeAmount, uint256 boostAmount, uint8 tier);
    event SetBoostMultiplier(uint256 boostMultiplier);
    event SetPerWinnerBoostLimit(uint256 perWinnerBoostLimit);
    event SetVaultEligibility(address indexed vault, bool isEligible);

    WorldVerifiedPrizeBoostHook public boostHook;
    MockWorldIdAddressBook public worldIdAddressBook;
    ERC20Mock public prizeToken;

    address public alice;
    address public bob;
    address public nonVerifiedAddress;
    address public owner;

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        nonVerifiedAddress = makeAddr("nonVerifiedAddress");
        owner = makeAddr("owner");

        worldIdAddressBook = new MockWorldIdAddressBook();
        vm.startPrank(alice);
        worldIdAddressBook.setAccountVerification(block.timestamp + 91 days);
        vm.stopPrank();
        vm.startPrank(bob);
        worldIdAddressBook.setAccountVerification(block.timestamp + 91 days);
        vm.stopPrank();

        prizeToken = new ERC20Mock();

        boostHook = new WorldVerifiedPrizeBoostHook(prizeToken, worldIdAddressBook, owner, 1, 100);
    }

    function testConstructor() external {
        WorldVerifiedPrizeBoostHook hook = new WorldVerifiedPrizeBoostHook(prizeToken, worldIdAddressBook, owner, 1, 100);
        assertEq(address(hook.PRIZE_TOKEN()), address(prizeToken));
        assertEq(address(hook.WORLD_ID_ADDRESS_BOOK()), address(worldIdAddressBook));
        assertEq(hook.owner(), owner);
        assertEq(hook.boostMultiplier(), 1);
        assertEq(hook.perWinnerBoostLimit(), 100);

        hook = new WorldVerifiedPrizeBoostHook(IERC20(address(1)), IWorldIdAddressBook(address(2)), address(3), 4, 5);
        assertEq(address(hook.PRIZE_TOKEN()), address(1));
        assertEq(address(hook.WORLD_ID_ADDRESS_BOOK()), address(2));
        assertEq(hook.owner(), address(3));
        assertEq(hook.boostMultiplier(), 4);
        assertEq(hook.perWinnerBoostLimit(), 5);
    }

    function testUpdateBoostMultiplier() external {
        vm.startPrank(owner);
        assertEq(boostHook.boostMultiplier(), 1);
        vm.expectEmit();
        emit SetBoostMultiplier(2);
        boostHook.setBoostMultiplier(2);
        assertEq(boostHook.boostMultiplier(), 2);
        vm.stopPrank();
    }

    function testUpdatePerWinnerBoostLimit() external {
        vm.startPrank(owner);
        assertEq(boostHook.perWinnerBoostLimit(), 100);
        vm.expectEmit();
        emit SetPerWinnerBoostLimit(200);
        boostHook.setPerWinnerBoostLimit(200);
        assertEq(boostHook.perWinnerBoostLimit(), 200);
        vm.stopPrank();
    }

    function testSetEligibleVault() external {
        vm.startPrank(owner);
        assertEq(boostHook.isEligibleVault(address(this)), false);

        vm.expectEmit();
        emit SetVaultEligibility(address(this), true);
        boostHook.setVaultEligibility(address(this), true);
        assertEq(boostHook.isEligibleVault(address(this)), true);

        vm.expectEmit();
        emit SetVaultEligibility(address(this), false);
        boostHook.setVaultEligibility(address(this), false);
        assertEq(boostHook.isEligibleVault(address(this)), false);

        vm.stopPrank();
    }

    function testWithdrawTokens() external {
        vm.startPrank(owner);
        prizeToken.mint(address(boostHook), 100);
        assertEq(prizeToken.balanceOf(address(boostHook)), 100);
        assertEq(prizeToken.balanceOf(bob), 0);
        vm.expectEmit();
        emit Transfer(address(boostHook), bob, 100);
        boostHook.withdraw(address(prizeToken), bob, 100);
        assertEq(prizeToken.balanceOf(address(boostHook)), 0);
        assertEq(prizeToken.balanceOf(bob), 100);
        vm.stopPrank();
    }

    function testSetBoostMultiplierFromNonOwner() external {
        vm.startPrank(alice);
        vm.expectRevert();
        boostHook.setBoostMultiplier(2);
        vm.stopPrank();
    }

    function testSetPerWinnerBoostLimitFromNonOwner() external {
        vm.startPrank(alice);
        vm.expectRevert();
        boostHook.setPerWinnerBoostLimit(200);
        vm.stopPrank();
    }

    function testSetVaultEligibilityFromNonOwner() external {
        vm.startPrank(alice);
        vm.expectRevert();
        boostHook.setVaultEligibility(address(this), true);
        vm.stopPrank();
    }

    function testWithdrawFromNonOwner() external {
        vm.startPrank(alice);
        prizeToken.mint(address(boostHook), 100);
        assertEq(prizeToken.balanceOf(address(boostHook)), 100);
        vm.expectRevert();
        boostHook.withdraw(address(prizeToken), alice, 100);
        vm.stopPrank();
    }

    function testBeforeClaimPrize() external view {
        (address recipient, bytes memory data) = boostHook.beforeClaimPrize(address(0), 0, 0, 0, address(0));
        assertEq(recipient, address(0));
        assertEq(data.length, 0);
    }

    // Boost Tests:

    function testAfterClaimPrizeNotEligible() external {
        assertEq(boostHook.isEligibleVault(address(this)), false);
        vm.recordLogs();
        boostHook.afterClaimPrize(alice, 1, 0, 10, bob, "");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0); // no boost happened if no log happened
    }

    function testAfterClaimPrizeAtLimit() external {
        vm.startPrank(owner);
        boostHook.setVaultEligibility(address(this), true);
        vm.stopPrank();
        assertEq(boostHook.isEligibleVault(address(this)), true);
        prizeToken.mint(address(boostHook), 1e10);

        // boost a prize so that alice's boost tokens received equals the boost limit
        vm.expectEmit();
        emit Transfer(address(boostHook), bob, 100);
        vm.expectEmit();
        emit VerifiedPrizeBoosted(alice, bob, address(this), 100, 100, 1);
        boostHook.afterClaimPrize(alice, 1, 0, 100, bob, "");

        // alice is at the limit, so the next hook won't do anything
        vm.recordLogs();
        boostHook.afterClaimPrize(alice, 1, 0, 10, bob, "");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0); // no boost happened if no log happened
    }

    function testAfterClaimPrizeNotVerified() external {
        vm.startPrank(owner);
        boostHook.setVaultEligibility(address(this), true);
        vm.stopPrank();
        assertEq(boostHook.isEligibleVault(address(this)), true);
        prizeToken.mint(address(boostHook), 1e10);

        // check if a small prize boost works normally
        vm.expectEmit();
        emit Transfer(address(boostHook), bob, 1);
        vm.expectEmit();
        emit VerifiedPrizeBoosted(alice, bob, address(this), 1, 1, 1);
        boostHook.afterClaimPrize(alice, 1, 0, 1, bob, "");

        // revoke alice's verification
        vm.startPrank(alice);
        worldIdAddressBook.setAccountVerification(block.timestamp);
        vm.stopPrank();

        // alice is no longer verified, so the next hook won't do anything
        vm.recordLogs();
        boostHook.afterClaimPrize(alice, 1, 0, 1, bob, "");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0); // no boost happened if no log happened
    }

    function testAfterClaimPrizeBoostMultiplier() external {
        vm.startPrank(owner);
        boostHook.setVaultEligibility(address(this), true);
        vm.stopPrank();
        assertEq(boostHook.isEligibleVault(address(this)), true);
        prizeToken.mint(address(boostHook), 1e10);

        uint256 prizeValue = 1;

        // check 1x
        vm.startPrank(owner);
        boostHook.setBoostMultiplier(1);
        vm.stopPrank();
        vm.expectEmit();
        emit Transfer(address(boostHook), bob, prizeValue * 1);
        vm.expectEmit();
        emit VerifiedPrizeBoosted(alice, bob, address(this), prizeValue, prizeValue * 1, 0);
        boostHook.afterClaimPrize(alice, 0, 0, prizeValue, bob, "");

        // check 2x
        vm.startPrank(owner);
        boostHook.setBoostMultiplier(2);
        vm.stopPrank();
        vm.expectEmit();
        emit Transfer(address(boostHook), bob, prizeValue * 2);
        vm.expectEmit();
        emit VerifiedPrizeBoosted(alice, bob, address(this), prizeValue, prizeValue * 2, 0);
        boostHook.afterClaimPrize(alice, 0, 0, prizeValue, bob, "");

        // check 5x
        vm.startPrank(owner);
        boostHook.setBoostMultiplier(5);
        vm.stopPrank();
        vm.expectEmit();
        emit Transfer(address(boostHook), bob, prizeValue * 5);
        vm.expectEmit();
        emit VerifiedPrizeBoosted(alice, bob, address(this), prizeValue, prizeValue * 5, 0);
        boostHook.afterClaimPrize(alice, 0, 0, prizeValue, bob, "");
    }

    function testAfterClaimPrizeReachesLimit() external {
        vm.startPrank(owner);
        boostHook.setVaultEligibility(address(this), true);
        vm.stopPrank();
        assertEq(boostHook.isEligibleVault(address(this)), true);
        prizeToken.mint(address(boostHook), 1e10);

        // boost a prize so that alice's boost tokens is one less than the boost limit
        assertEq(boostHook.boostTokensReceived(alice), 0);
        assertEq(boostHook.perWinnerBoostLimit(), 100);
        vm.expectEmit();
        emit Transfer(address(boostHook), bob, 99);
        vm.expectEmit();
        emit VerifiedPrizeBoosted(alice, bob, address(this), 99, 99, 1);
        boostHook.afterClaimPrize(alice, 1, 0, 99, bob, "");

        // alice is just below the limit, so the next prize boost will be limited at 1 token
        assertEq(boostHook.boostTokensReceived(alice), 99);
        vm.expectEmit();
        emit Transfer(address(boostHook), bob, 1);
        vm.expectEmit();
        emit VerifiedPrizeBoosted(alice, bob, address(this), 100, 1, 1);
        boostHook.afterClaimPrize(alice, 1, 0, 100, bob, "");
        assertEq(boostHook.boostTokensReceived(alice), 100);
    }

    function testAfterClaimPrizeZeroBoost() external {
        vm.startPrank(owner);
        boostHook.setVaultEligibility(address(this), true);
        vm.stopPrank();
        assertEq(boostHook.isEligibleVault(address(this)), true);
        prizeToken.mint(address(boostHook), 1e10);

        // check if a small prize boost works normally
        vm.expectEmit();
        emit Transfer(address(boostHook), bob, 1);
        vm.expectEmit();
        emit VerifiedPrizeBoosted(alice, bob, address(this), 1, 1, 1);
        boostHook.afterClaimPrize(alice, 1, 0, 1, bob, "");

        // If the boost is zero, nothing will happen
        vm.startPrank(owner);
        boostHook.setBoostMultiplier(0);
        vm.stopPrank();
        vm.recordLogs();
        boostHook.afterClaimPrize(alice, 1, 0, 1, bob, "");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0); // no boost happened if no log happened
    }

    function testAfterClaimPrizeNotEnoughBalance() external {
        vm.startPrank(owner);
        boostHook.setVaultEligibility(address(this), true);
        vm.stopPrank();
        assertEq(boostHook.isEligibleVault(address(this)), true);
        prizeToken.mint(address(boostHook), 1);

        // check if a 1 token boost works normally
        vm.expectEmit();
        emit Transfer(address(boostHook), bob, 1);
        vm.expectEmit();
        emit VerifiedPrizeBoosted(alice, bob, address(this), 1, 1, 1);
        boostHook.afterClaimPrize(alice, 1, 0, 1, bob, "");

        // There are no more tokens in the contract, so the next boost won't work
        assertEq(prizeToken.balanceOf(address(boostHook)), 0);
        vm.recordLogs();
        boostHook.afterClaimPrize(alice, 1, 0, 1, bob, "");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0); // no boost happened if no log happened
    }

}
