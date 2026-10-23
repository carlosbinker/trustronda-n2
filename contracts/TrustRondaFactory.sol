// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TrustRonda} from "./TrustRonda.sol";

/// @notice El token no está habilitado para crear rondas.
/// @param token Token pedido.
error TokenNotAllowed(address token);

/// @notice Se pasó la dirección cero como token.
error ZeroTokenAddress();

/// @title TrustRondaFactory
/// @author Carlos Binker
/// @notice Crea rondas `TrustRonda` y lleva el registro de todas, para que el frontend las encuentre sin indexador.
/// @dev Roles y privilegios:
///      - `owner` (OpenZeppelin `Ownable`): su ÚNICO privilegio es habilitar o deshabilitar tokens con
///        `setTokenAllowed`. No tiene ningún poder sobre las rondas ya creadas ni sobre sus fondos.
///      - Cualquier cuenta: puede crear rondas con un token habilitado y queda como `organizer` de esa ronda.
///      La lista blanca de tokens evita rondas con tokens fee-on-transfer, rebasing o maliciosos, que romperían
///      la contabilidad de `TrustRonda` (que asume que llega exactamente el monto transferido).
contract TrustRondaFactory is Ownable {
    // ─────────────────────────────────────────────────────────────────────
    // Variables de estado
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Tokens habilitados para crear rondas.
    mapping(address token => bool allowed) public isTokenAllowed;

    /// @notice Todas las rondas creadas, en orden de creación.
    address[] private _rondas;

    /// @notice Marca las direcciones creadas por esta factory (para que el frontend o un tercero validen
    ///         que una ronda es legítima).
    mapping(address ronda => bool created) public isRonda;

    // ─────────────────────────────────────────────────────────────────────
    // Eventos
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Se creó una ronda nueva.
    /// @param ronda Dirección del contrato `TrustRonda` desplegado.
    /// @param organizer Cuenta que la creó.
    /// @param token Token de los aportes.
    /// @param contributionAmount Aporte por turno.
    /// @param collateralAmount Garantía por miembro.
    /// @param maxMembers Cupo de miembros.
    /// @param roundDuration Duración de cada turno, en segundos.
    /// @param joinDeadline Vencimiento de la inscripción.
    event RondaCreated(
        address indexed ronda,
        address indexed organizer,
        address indexed token,
        uint256 contributionAmount,
        uint256 collateralAmount,
        uint8 maxMembers,
        uint64 roundDuration,
        uint64 joinDeadline
    );

    /// @notice Se habilitó o deshabilitó un token.
    /// @param token Token afectado.
    /// @param allowed Nuevo estado.
    event TokenAllowed(address indexed token, bool allowed);

    // ─────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Despliega la factory y opcionalmente habilita un primer token.
    /// @param initialOwner Cuenta que va a poder administrar la lista de tokens (OpenZeppelin v5 lo exige explícito).
    /// @param initialToken Token a habilitar al desplegar; `address(0)` para no habilitar ninguno.
    constructor(address initialOwner, address initialToken) Ownable(initialOwner) {
        if (initialToken != address(0)) {
            isTokenAllowed[initialToken] = true;
            emit TokenAllowed(initialToken, true);
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Funciones external que modifican estado
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Crea una ronda nueva; quien llama queda como organizador.
    /// @dev Interacción entre contratos: despliega `TrustRonda` con `new`. Las validaciones de los parámetros
    ///      viven en el constructor de `TrustRonda`, así no se duplican; si alguno es inválido, revierte todo.
    /// @param token Token ERC20 habilitado.
    /// @param contributionAmount Aporte por turno.
    /// @param collateralAmount Garantía por miembro (>= aporte).
    /// @param maxMembers Cupo de miembros.
    /// @param roundDuration Duración de cada turno, en segundos.
    /// @param joinWindow Tiempo para completar el cupo, en segundos.
    /// @return ronda Dirección de la ronda creada.
    function createRonda(
        address token,
        uint256 contributionAmount,
        uint256 collateralAmount,
        uint8 maxMembers,
        uint64 roundDuration,
        uint64 joinWindow
    ) external returns (address ronda) {
        if (!isTokenAllowed[token]) revert TokenNotAllowed(token);

        TrustRonda newRonda = new TrustRonda(
            msg.sender, IERC20(token), contributionAmount, collateralAmount, maxMembers, roundDuration, joinWindow
        );
        ronda = address(newRonda);

        _rondas.push(ronda);
        isRonda[ronda] = true;

        emit RondaCreated(
            ronda,
            msg.sender,
            token,
            contributionAmount,
            collateralAmount,
            maxMembers,
            roundDuration,
            newRonda.joinDeadline()
        );
    }

    /// @notice Habilita o deshabilita un token para rondas futuras. Las rondas existentes no se ven afectadas.
    /// @dev Solo `owner`.
    /// @param token Token a modificar.
    /// @param allowed true para habilitar, false para deshabilitar.
    function setTokenAllowed(address token, bool allowed) external onlyOwner {
        if (token == address(0)) revert ZeroTokenAddress();
        isTokenAllowed[token] = allowed;
        emit TokenAllowed(token, allowed);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Funciones external view
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Cantidad de rondas creadas.
    /// @return Total de rondas.
    function rondasCount() external view returns (uint256) {
        return _rondas.length;
    }

    /// @notice Devuelve una página de rondas, para no devolver un array sin límite.
    /// @param offset Índice desde el que empezar.
    /// @param limit Cantidad máxima de rondas a devolver.
    /// @return page Direcciones de las rondas en ese rango (puede venir vacío o más corto).
    function getRondas(uint256 offset, uint256 limit) external view returns (address[] memory page) {
        uint256 total = _rondas.length;
        if (offset >= total) return new address[](0);
        // se compara contra lo que queda para que `offset + limit` nunca pueda hacer overflow
        uint256 end = limit > total - offset ? total : offset + limit;
        page = new address[](end - offset);
        for (uint256 i = offset; i < end;) {
            page[i - offset] = _rondas[i];
            unchecked {
                ++i;
            }
        }
    }
}
