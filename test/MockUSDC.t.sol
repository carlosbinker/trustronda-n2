// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "../contracts/MockUSDC.sol";

/// @title MockUSDCTest
/// @notice Tests del token de prueba y su faucet con cooldown.
contract MockUSDCTest is Test {
    MockUSDC internal usdc;
    address internal user = makeAddr("user");

    event FaucetClaimed(address indexed to, uint256 amount);

    function setUp() public {
        vm.warp(1_700_000_000);
        usdc = new MockUSDC();
    }

    function test_Metadata() public view {
        assertEq(usdc.name(), "Test USD");
        assertEq(usdc.symbol(), "tUSD");
        assertEq(usdc.decimals(), 6);
    }

    function test_Faucet_MintsAndEmits() public {
        vm.expectEmit(true, false, false, true, address(usdc));
        emit FaucetClaimed(user, 1_000e6);
        vm.prank(user);
        usdc.faucet();
        assertEq(usdc.balanceOf(user), 1_000e6);
        assertEq(usdc.lastFaucetClaim(user), block.timestamp);
    }

    function test_RevertWhen_FaucetDuringCooldown() public {
        vm.prank(user);
        usdc.faucet();
        vm.warp(block.timestamp + 1 days - 1);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(MockUSDC.FaucetCooldown.selector, 1_700_000_000 + 1 days));
        usdc.faucet();
    }

    function test_Faucet_AfterCooldown() public {
        vm.startPrank(user);
        usdc.faucet();
        vm.warp(block.timestamp + 1 days);
        usdc.faucet();
        vm.stopPrank();
        assertEq(usdc.balanceOf(user), 2_000e6);
    }
}
