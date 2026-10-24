// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ITrustRondaDrawer
/// @author Carlos Binker
/// @notice Interfaz que usa cada `TrustRonda` para pedirle a la factory el sorteo del orden de cobro.
/// @dev La implementa `TrustRondaFactory`, que es el único consumidor de Chainlink VRF del sistema.
interface ITrustRondaDrawer {
    /// @notice Pide un número aleatorio a Chainlink VRF para sortear el orden de cobro de la ronda que llama.
    /// @dev No devuelve el requestId: la factory lo registra en `drawRequestOf(ronda)` y lo emite en `DrawRequested`.
    function requestDraw() external;
}
