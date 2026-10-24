// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "../../contracts/MockUSDC.sol";
import {TrustRonda} from "../../contracts/TrustRonda.sol";
import {TrustRondaFactory} from "../../contracts/TrustRondaFactory.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

/// @title BaseTest
/// @notice Setup común: despliega tUSD, el coordinador mock de Chainlink VRF v2.5 (oficial de Chainlink), una
///         suscripción con fondos y la factory como consumidor; crea usuarios con saldo y ayuda a crear rondas.
abstract contract BaseTest is Test {
    MockUSDC internal usdc;
    TrustRondaFactory internal factory;
    VRFCoordinatorV2_5Mock internal vrf;
    uint256 internal subId;
    bytes32 internal constant KEY_HASH = keccak256("test-gas-lane");

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

        // Chainlink VRF v2.5 mock: baseFee 0,1 LINK, gasPrice 1 gwei, 1 LINK = 0,004 ETH
        vrf = new VRFCoordinatorV2_5Mock(0.1 ether, 1e9, 4e15);
        subId = vrf.createSubscription();
        vrf.fundSubscription(subId, 1_000 ether);

        factory = new TrustRondaFactory(owner, address(usdc), address(vrf), KEY_HASH, subId, false);
        vrf.addConsumer(subId, address(factory));

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

    /// @dev Simula la respuesta de Chainlink VRF con el número aleatorio que genera el mock.
    function _fulfill(TrustRonda ronda) internal {
        vrf.fulfillRandomWords(factory.drawRequestOf(address(ronda)), address(factory));
    }

    /// @dev Simula la respuesta de Chainlink VRF con un número elegido (para fuzzing).
    function _fulfillWith(TrustRonda ronda, uint256 word) internal {
        uint256[] memory words = new uint256[](1);
        words[0] = word;
        vrf.fulfillRandomWordsWithOverride(factory.drawRequestOf(address(ronda)), address(factory), words);
    }

    /// @dev Crea la ronda estándar, la llena con alice, bob y carol y entrega el sorteo de VRF.
    ///      El orden de cobro sale del sorteo: los tests lo leen con `getMembers()`.
    function _createActiveRonda() internal returns (TrustRonda ronda) {
        ronda = _createDefaultRonda();
        _join(ronda, alice);
        _join(ronda, bob);
        _join(ronda, carol);
        _fulfill(ronda);
    }
}
