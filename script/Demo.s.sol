// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MockUSDC} from "../contracts/MockUSDC.sol";
import {TrustRonda, RondaStatus} from "../contracts/TrustRonda.sol";
import {TrustRondaFactory} from "../contracts/TrustRondaFactory.sol";

/// @title DemoBase
/// @notice Utilidades comunes de la demo on-chain: dos wallets de testnet (PRIVATE_KEY y PRIVATE_KEY_2) y las
///         direcciones de deployments/<chainId>.json.
abstract contract DemoBase is Script {
    uint256 internal constant CONTRIBUTION = 50e6; // 50 tUSD
    uint256 internal constant COLLATERAL = 50e6; // 50 tUSD
    uint64 internal constant ROUND = 1 days;
    uint64 internal constant JOIN_WINDOW = 1 days;

    uint256 internal pkA;
    uint256 internal pkB;
    MockUSDC internal usdc;
    TrustRondaFactory internal factory;

    function _load() internal {
        pkA = vm.envUint("PRIVATE_KEY");
        pkB = vm.envUint("PRIVATE_KEY_2");
        // Lectura intencional del archivo que generó Deploy; fs_permissions la limita a ./deployments
        // forge-lint: disable-next-line(unsafe-cheatcode)
        string memory json = vm.readFile(string.concat("./deployments/", vm.toString(block.chainid), ".json"));
        usdc = MockUSDC(vm.parseJsonAddress(json, ".MockUSDC"));
        factory = TrustRondaFactory(vm.parseJsonAddress(json, ".TrustRondaFactory"));
    }

    function _pkOf(address who) internal view returns (uint256) {
        return who == vm.addr(pkA) ? pkA : pkB;
    }

    function _approveAnd(uint256 pk, TrustRonda ronda, uint256 amount, bool isJoin) internal {
        vm.startBroadcast(pk);
        usdc.approve(address(ronda), amount);
        if (isJoin) ronda.join();
        else ronda.contribute();
        vm.stopBroadcast();
    }
}

/// @title DemoStart
/// @notice Paso 1 de la demo: faucet → createRonda (2 miembros) → join x2. Con el segundo join la ronda pide el
///         sorteo a Chainlink VRF y queda en `Drawing`.
/// @dev forge script script/Demo.s.sol:DemoStart --rpc-url sepolia --broadcast
///      Después esperar 1 o 2 minutos a que VRF responda (se ve en vrf.chain.link) y correr DemoFinish.
contract DemoStart is DemoBase {
    function run() external {
        _load();
        uint256 needed = COLLATERAL + CONTRIBUTION * 2;
        if (usdc.balanceOf(vm.addr(pkA)) < needed) {
            vm.broadcast(pkA);
            usdc.faucet();
        }
        if (usdc.balanceOf(vm.addr(pkB)) < needed) {
            vm.broadcast(pkB);
            usdc.faucet();
        }

        vm.broadcast(pkA);
        TrustRonda ronda =
            TrustRonda(factory.createRonda(address(usdc), CONTRIBUTION, COLLATERAL, 2, ROUND, JOIN_WINDOW));

        _approveAnd(pkA, ronda, COLLATERAL, true);
        _approveAnd(pkB, ronda, COLLATERAL, true); // completa el cupo → factory.requestDraw() → Chainlink VRF

        console.log("Ronda creada:", address(ronda));
        console.log("Esperar el sorteo de Chainlink VRF y correr:");
        console.log("  RONDA=<direccion> forge script script/Demo.s.sol:DemoFinish --rpc-url sepolia --broadcast");
    }
}

/// @title DemoFinish
/// @notice Paso 2 de la demo (con el orden ya sorteado por VRF): turno 1 (contribute x2, closeRound, withdraw),
///         turno 2 (contribute x2, closeRound → Completed) y retiros finales de pozo y garantía.
/// @dev RONDA=0x... forge script script/Demo.s.sol:DemoFinish --rpc-url sepolia --broadcast
contract DemoFinish is DemoBase {
    function run() external {
        _load();
        TrustRonda ronda = TrustRonda(vm.envAddress("RONDA"));
        require(ronda.status() == RondaStatus.Active, "El sorteo de VRF todavia no llego: esperar y reintentar");

        address[] memory order = ronda.getMembers(); // orden sorteado por Chainlink VRF
        console.log("Cobra en el turno 1:", order[0]);
        console.log("Cobra en el turno 2:", order[1]);

        for (uint256 r; r < 2; ++r) {
            _approveAnd(pkA, ronda, CONTRIBUTION, false);
            _approveAnd(pkB, ronda, CONTRIBUTION, false);
            vm.broadcast(pkA); // cualquiera puede cerrar
            ronda.closeRound();
            vm.broadcast(_pkOf(order[r])); // el beneficiario retira su pozo (pull payment)
            ronda.withdraw();
        }
        // Retiro final de la garantía del que cobró primero (el segundo ya la retiró junto con su pozo)
        vm.broadcast(_pkOf(order[0]));
        ronda.withdraw();

        console.log("Estado final (3 = Completed):", uint8(ronda.status()));
        console.log("Saldo tUSD de la ronda:", usdc.balanceOf(address(ronda)));
    }
}
