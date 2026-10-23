// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MockUSDC} from "../contracts/MockUSDC.sol";
import {TrustRonda} from "../contracts/TrustRonda.sol";
import {TrustRondaFactory} from "../contracts/TrustRondaFactory.sol";

/// @title Demo
/// @notice Ejecuta ON-CHAIN el flujo principal completo con dos wallets de testnet, para dejar transacciones
///         reales que se puedan linkear en el README (checklist A y F). Es un complemento del frontend, no lo reemplaza.
/// @dev Flujo: faucet → createRonda (2 miembros) → join x2 → turno 0 (contribute x2, closeRound, withdraw)
///      → turno 1 (contribute x2, closeRound) → withdraw x2 (pozo + garantía).
///      Como en cada turno pagan los dos, se puede cerrar sin esperar el vencimiento.
///      Uso: forge script script/Demo.s.sol --rpc-url sepolia --broadcast
///      Requiere PRIVATE_KEY y PRIVATE_KEY_2 en .env, y que deployments/<chainId>.json exista (lo genera Deploy).
contract Demo is Script {
    uint256 internal constant CONTRIBUTION = 50e6; // 50 tUSD
    uint256 internal constant COLLATERAL = 50e6; // 50 tUSD
    uint64 internal constant ROUND = 1 days;
    uint64 internal constant JOIN_WINDOW = 1 days;

    function run() external {
        uint256 pkA = vm.envUint("PRIVATE_KEY");
        uint256 pkB = vm.envUint("PRIVATE_KEY_2");
        address a = vm.addr(pkA);
        address b = vm.addr(pkB);

        string memory json = vm.readFile(string.concat("./deployments/", vm.toString(block.chainid), ".json"));
        MockUSDC usdc = MockUSDC(vm.parseJsonAddress(json, ".MockUSDC"));
        TrustRondaFactory factory = TrustRondaFactory(vm.parseJsonAddress(json, ".TrustRondaFactory"));

        // 1) Fondos de prueba (solo si hacen falta: el faucet tiene cooldown de 1 día)
        uint256 needed = COLLATERAL + CONTRIBUTION * 2;
        if (usdc.balanceOf(a) < needed) {
            vm.broadcast(pkA);
            usdc.faucet();
        }
        if (usdc.balanceOf(b) < needed) {
            vm.broadcast(pkB);
            usdc.faucet();
        }

        // 2) A crea la ronda (interacción factory → new TrustRonda)
        vm.broadcast(pkA);
        TrustRonda ronda =
            TrustRonda(factory.createRonda(address(usdc), CONTRIBUTION, COLLATERAL, 2, ROUND, JOIN_WINDOW));
        console.log("Ronda creada:", address(ronda));

        // 3) Inscripción: A cobra en el turno 0 y B en el turno 1. Con B se completa el cupo y arranca la ronda.
        _approveAndJoin(pkA, usdc, ronda);
        _approveAndJoin(pkB, usdc, ronda);

        // 4) Turno 0: pagan los dos, se cierra y A retira su pozo
        _approveAndContribute(pkA, usdc, ronda);
        _approveAndContribute(pkB, usdc, ronda);
        vm.broadcast(pkB); // cualquiera puede cerrar
        ronda.closeRound();
        vm.broadcast(pkA);
        ronda.withdraw();

        // 5) Turno 1: pagan los dos y se cierra; la ronda queda Completed
        _approveAndContribute(pkA, usdc, ronda);
        _approveAndContribute(pkB, usdc, ronda);
        vm.broadcast(pkA);
        ronda.closeRound();

        // 6) Retiros finales: A recupera su garantía; B, su pozo + su garantía
        vm.broadcast(pkA);
        ronda.withdraw();
        vm.broadcast(pkB);
        ronda.withdraw();

        console.log("Estado final (2 = Completed):", uint8(ronda.status()));
        console.log("Saldo tUSD de la ronda:", usdc.balanceOf(address(ronda)));
        console.log("Wallet A:", a);
        console.log("Wallet B:", b);
    }

    function _approveAndJoin(uint256 pk, MockUSDC usdc, TrustRonda ronda) internal {
        vm.startBroadcast(pk);
        usdc.approve(address(ronda), COLLATERAL);
        ronda.join();
        vm.stopBroadcast();
    }

    function _approveAndContribute(uint256 pk, MockUSDC usdc, TrustRonda ronda) internal {
        vm.startBroadcast(pk);
        usdc.approve(address(ronda), CONTRIBUTION);
        ronda.contribute();
        vm.stopBroadcast();
    }
}
