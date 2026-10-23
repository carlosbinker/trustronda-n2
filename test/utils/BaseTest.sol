// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "../../contracts/MockUSDC.sol";
import {TrustRonda} from "../../contracts/TrustRonda.sol";
import {TrustRondaFactory} from "../../contracts/TrustRondaFactory.sol";

/// @title BaseTest
/// @notice Setup común: despliega tUSD y la factory, crea usuarios con saldo y ayuda a crear rondas.
abstract contract BaseTest is Test {
    MockUSDC internal usdc;
    TrustRondaFactory internal factory;

    address internal owner = makeAddr("owner");
    address internal organizer = makeAddr("organizer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal outsider = makeAddr("outsider");

    uint256 internal constant CONTRIBUTION = 100e6; // 100 tUSD
    uint256 internal constant COLLATERAL = 100e6; // 100 tUSD
    uint8 internal constant MEMBERS = 3;
    uint64 internal constant ROUND = 1 days;
    uint64 internal constant JOIN_WINDOW = 7 days;

    function setUp() public virtual {
        // Arranca en un timestamp realista: con 0 el cooldown del faucet sería ambiguo.
        vm.warp(1_700_000_000);
        usdc = new MockUSDC();
        factory = new TrustRondaFactory(owner, address(usdc));

        address[4] memory users = [alice, bob, carol, outsider];
        for (uint256 i; i < users.length; ++i) {
            vm.prank(users[i]);
            usdc.faucet(); // 1.000 tUSD a cada uno
        }
    }

    /// @dev Crea la ronda estándar de 3 miembros desde `organizer`.
    function _createDefaultRonda() internal returns (TrustRonda ronda) {
        vm.prank(organizer);
        ronda = TrustRonda(factory.createRonda(address(usdc), CONTRIBUTION, COLLATERAL, MEMBERS, ROUND, JOIN_WINDOW));
    }

    /// @dev `user` aprueba y se inscribe.
    function _join(TrustRonda ronda, address user) internal {
        vm.startPrank(user);
        usdc.approve(address(ronda), ronda.collateralAmount());
        ronda.join();
        vm.stopPrank();
    }

    /// @dev `user` aprueba y paga el aporte del turno.
    function _contribute(TrustRonda ronda, address user) internal {
        vm.startPrank(user);
        usdc.approve(address(ronda), ronda.contributionAmount());
        ronda.contribute();
        vm.stopPrank();
    }

    /// @dev Crea la ronda estándar y la llena con alice, bob y carol (en ese orden de cobro).
    function _createActiveRonda() internal returns (TrustRonda ronda) {
        ronda = _createDefaultRonda();
        _join(ronda, alice);
        _join(ronda, bob);
        _join(ronda, carol);
    }
}
