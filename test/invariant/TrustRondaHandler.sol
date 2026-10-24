// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "../../contracts/MockUSDC.sol";
import {TrustRonda, RondaStatus} from "../../contracts/TrustRonda.sol";
import {TrustRondaFactory} from "../../contracts/TrustRondaFactory.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

/// @title TrustRondaHandler
/// @notice Handler del invariant testing: expone acciones válidas (con inputs acotados) que el fuzzer
///         combina en secuencias aleatorias.
contract TrustRondaHandler is Test {
    TrustRonda public ronda;
    MockUSDC public usdc;
    address[] public actors;
    TrustRondaFactory public factory;
    VRFCoordinatorV2_5Mock public vrf;

    /// @notice Contadores de llamadas exitosas, para ver en el reporte que el fuzzer realmente recorrió el flujo.
    mapping(bytes32 action => uint256 calls) public calls;

    constructor(
        TrustRonda ronda_,
        MockUSDC usdc_,
        address[] memory actors_,
        TrustRondaFactory factory_,
        VRFCoordinatorV2_5Mock vrf_
    ) {
        ronda = ronda_;
        usdc = usdc_;
        actors = actors_;
        factory = factory_;
        vrf = vrf_;
    }

    /// @dev Simula la respuesta de Chainlink VRF con un número elegido por el fuzzer.
    function fulfill(uint256 word) external {
        if (ronda.status() != RondaStatus.Drawing) return;
        uint256[] memory words = new uint256[](1);
        words[0] = word;
        vrf.fulfillRandomWordsWithOverride(factory.drawRequestOf(address(ronda)), address(factory), words);
        calls["fulfill"]++;
    }

    function join(uint256 actorSeed) external {
        address actor = actors[bound(actorSeed, 0, actors.length - 1)];
        if (ronda.status() != RondaStatus.Open || ronda.getMemberInfo(actor).isMember) return;
        if (block.timestamp > ronda.joinDeadline()) return;
        vm.startPrank(actor);
        usdc.approve(address(ronda), ronda.collateralAmount());
        ronda.join();
        vm.stopPrank();
        calls["join"]++;
    }

    /// @dev Busca, a partir de la semilla, el primer miembro que todavía no pagó el turno, para que el fuzzer
    ///      avance el flujo en vez de gastar llamadas en casos que la propia función filtraría.
    function contribute(uint256 actorSeed) external {
        if (ronda.status() != RondaStatus.Active || block.timestamp > ronda.roundDeadline()) return;
        address[] memory members = ronda.getMembers();
        uint8 round = ronda.currentRound();
        for (uint256 k; k < members.length; ++k) {
            address actor = members[(actorSeed + k) % members.length];
            if (ronda.hasPaid(round, actor)) continue;
            vm.startPrank(actor);
            usdc.approve(address(ronda), ronda.contributionAmount());
            ronda.contribute();
            vm.stopPrank();
            calls["contribute"]++;
            return;
        }
    }

    /// @dev Si faltan pagos, avanza el tiempo hasta después del vencimiento (camino de impago y garantía).
    function closeRound() external {
        if (ronda.status() != RondaStatus.Active) return;
        if (ronda.paidCount() < ronda.maxMembers() && block.timestamp <= ronda.roundDeadline()) {
            vm.warp(uint256(ronda.roundDeadline()) + 1);
        }
        ronda.closeRound();
        calls["closeRound"]++;
    }

    function withdraw(uint256 actorSeed) external {
        address actor = actors[bound(actorSeed, 0, actors.length - 1)];
        (uint256 p, uint256 c) = ronda.withdrawable(actor);
        if (p + c == 0) return;
        vm.prank(actor);
        ronda.withdraw();
        calls["withdraw"]++;
    }

    /// @dev Solo se cancela después de joinDeadline (camino "cualquiera cancela"). Si el organizador pudiera
    ///      cancelar en cualquier momento, la mayoría de las secuencias terminarían en Cancelled en las primeras
    ///      llamadas y el fuzzer casi nunca llegaría a los turnos.
    function cancel(uint256 actorSeed) external {
        RondaStatus st = ronda.status();
        bool openExpired = st == RondaStatus.Open && block.timestamp > ronda.joinDeadline();
        bool drawExpired =
            st == RondaStatus.Drawing && block.timestamp > ronda.drawRequestedAt() + ronda.DRAW_TIMEOUT();
        if (!openExpired && !drawExpired) return;
        vm.prank(actors[bound(actorSeed, 0, actors.length - 1)]);
        ronda.cancel();
        calls["cancel"]++;
    }

    function warp(uint256 secondsAhead) external {
        vm.warp(block.timestamp + bound(secondsAhead, 1, 12 hours));
        calls["warp"]++;
    }
}
