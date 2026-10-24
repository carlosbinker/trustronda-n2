// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./utils/BaseTest.sol";
import {TrustRonda, RondaStatus} from "../contracts/TrustRonda.sol";

/// @title TrustRondaFuzzTest
/// @notice Fuzz tests (property-based): con parámetros y patrones de pago aleatorios, el dinero se conserva.
contract TrustRondaFuzzTest is BaseTest {
    /// @notice Propiedad: para CUALQUIER configuración válida y CUALQUIER patrón de pagos e impagos,
    ///         al final nadie gana ni pierde dinero de la nada: la suma de saldos se conserva y el contrato
    ///         queda en cero después de que todos retiran.
    /// @param contribution Aporte por turno (se acota a 1..1.000 tUSD).
    /// @param extraCollateral Garantía adicional sobre el aporte (0..1.000 tUSD).
    /// @param members Cupo (2..12).
    /// @param payMask Bits que indican quién paga en cada turno (bit = turno * 12 + miembro).
    function testFuzz_MoneyIsConserved(uint256 contribution, uint256 extraCollateral, uint8 members, uint256 payMask)
        public
    {
        contribution = bound(contribution, 1, 1_000e6);
        extraCollateral = bound(extraCollateral, 0, 1_000e6);
        members = uint8(bound(members, 2, 12));
        uint256 collateral = contribution + extraCollateral;

        vm.prank(organizer);
        TrustRonda ronda = TrustRonda(
            factory.createRonda(address(usdc), contribution, collateral, members, ROUND, JOIN_WINDOW)
        );

        // Cada miembro arranca con suficiente saldo para pagar todo (garantía + todos los turnos)
        address[] memory users = new address[](members);
        uint256 perUser = collateral + contribution * members;
        for (uint256 i; i < members; ++i) {
            users[i] = makeAddr(string.concat("member", vm.toString(i)));
            deal(address(usdc), users[i], perUser);
            _join(ronda, users[i]);
        }
        _fulfillWith(ronda, payMask); // el número de VRF también es aleatorio
        assertEq(uint8(ronda.status()), uint8(RondaStatus.Active));
        users = ronda.getMembers(); // orden de cobro sorteado

        for (uint256 r; r < members; ++r) {
            for (uint256 i; i < members; ++i) {
                if ((payMask >> ((r * 12 + i) % 256)) & 1 == 1) _contribute(ronda, users[i]);
            }
            if (ronda.paidCount() < members) vm.warp(ronda.roundDeadline() + 1);
            ronda.closeRound();
        }
        assertEq(uint8(ronda.status()), uint8(RondaStatus.Completed));

        uint256 total;
        for (uint256 i; i < members; ++i) {
            (uint256 payout, uint256 coll) = ronda.withdrawable(users[i]);
            if (payout + coll > 0) {
                vm.prank(users[i]);
                ronda.withdraw();
            }
            total += usdc.balanceOf(users[i]);
        }
        assertEq(usdc.balanceOf(address(ronda)), 0, "el contrato no debe retener fondos");
        assertEq(total, perUser * members, "la suma de saldos se conserva");
    }

    /// @notice Propiedad: si todos pagan siempre, cada miembro termina exactamente con lo que tenía.
    /// @param contribution Aporte por turno (1..1.000 tUSD).
    /// @param members Cupo (2..12).
    function testFuzz_AllPay_EveryoneEndsEven(uint256 contribution, uint8 members) public {
        contribution = bound(contribution, 1, 1_000e6);
        members = uint8(bound(members, 2, 12));

        vm.prank(organizer);
        TrustRonda ronda =
            TrustRonda(factory.createRonda(address(usdc), contribution, contribution, members, ROUND, JOIN_WINDOW));

        address[] memory users = new address[](members);
        uint256 perUser = contribution * (members + 1);
        for (uint256 i; i < members; ++i) {
            users[i] = makeAddr(string.concat("payer", vm.toString(i)));
            deal(address(usdc), users[i], perUser);
            _join(ronda, users[i]);
        }
        _fulfill(ronda);
        for (uint256 r; r < members; ++r) {
            for (uint256 i; i < members; ++i) {
                _contribute(ronda, users[i]);
            }
            ronda.closeRound();
        }
        for (uint256 i; i < members; ++i) {
            vm.prank(users[i]);
            ronda.withdraw();
            assertEq(usdc.balanceOf(users[i]), perUser);
        }
    }

    /// @notice Propiedad: antes del vencimiento y con pagos faltantes, closeRound siempre revierte.
    /// @param elapsed Tiempo transcurrido dentro del turno.
    function testFuzz_CannotCloseEarly(uint64 elapsed) public {
        TrustRonda ronda = _createActiveRonda();
        _contribute(ronda, alice);
        elapsed = uint64(bound(elapsed, 0, ROUND));
        vm.warp(block.timestamp + elapsed);
        vm.expectRevert();
        ronda.closeRound();
    }

    /// @notice Propiedad: para CUALQUIER número de VRF y cualquier cupo, el sorteo es una permutación de los
    ///         inscriptos (nadie desaparece ni se duplica) y cada `position` coincide con su lugar.
    /// @param word Número aleatorio entregado por VRF.
    /// @param members Cupo (2..12).
    function testFuzz_DrawIsPermutation(uint256 word, uint8 members) public {
        members = uint8(bound(members, 2, 12));
        vm.prank(organizer);
        TrustRonda ronda =
            TrustRonda(factory.createRonda(address(usdc), 1e6, 1e6, members, ROUND, JOIN_WINDOW));
        address[] memory joined = new address[](members);
        for (uint256 i; i < members; ++i) {
            joined[i] = makeAddr(string.concat("p", vm.toString(i)));
            deal(address(usdc), joined[i], 1e6);
            _join(ronda, joined[i]);
        }
        _fulfillWith(ronda, word);
        // si el callback se quedara sin gas (CALLBACK_GAS_LIMIT), el mock no revierte: la ronda seguiría en Drawing
        assertEq(uint8(ronda.status()), uint8(RondaStatus.Active), "el callback de VRF entra en el gas limit");

        address[] memory order = ronda.getMembers();
        assertEq(order.length, members);
        for (uint256 i; i < members; ++i) {
            assertEq(ronda.getMemberInfo(order[i]).position, i);
            uint256 seen;
            for (uint256 k; k < members; ++k) {
                if (order[k] == joined[i]) ++seen;
            }
            assertEq(seen, 1, "cada inscripto aparece exactamente una vez");
        }
    }
}
