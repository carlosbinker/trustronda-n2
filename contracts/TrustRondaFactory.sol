// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVRFCoordinatorV2Plus} from
    "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {TrustRonda} from "./TrustRonda.sol";
import {ITrustRondaDrawer} from "./interfaces/ITrustRondaDrawer.sol";

/// @notice El token no está habilitado para crear rondas.
/// @param token Token pedido.
error TokenNotAllowed(address token);

/// @notice Se pasó la dirección cero como token.
error ZeroTokenAddress();

/// @notice Se pasó la dirección cero como coordinador de Chainlink VRF.
error ZeroCoordinatorAddress();

/// @notice Solo una ronda creada por esta factory puede pedir un sorteo.
/// @param caller Cuenta que llamó.
error NotRonda(address caller);

/// @notice Solo el coordinador de Chainlink VRF puede entregar números aleatorios.
/// @param have Cuenta que llamó.
/// @param want Coordinador esperado.
error OnlyCoordinatorCanFulfill(address have, address want);

/// @title TrustRondaFactory
/// @author Carlos Binker
/// @notice Crea rondas `TrustRonda`, lleva el registro de todas y sortea el orden de cobro de cada una con
///         Chainlink VRF v2.5, para que nadie, ni el organizador ni los miembros, pueda elegir quién cobra primero.
/// @dev Roles y privilegios:
///      - `owner` (OpenZeppelin `Ownable`): su ÚNICO privilegio es habilitar o deshabilitar tokens con
///        `setTokenAllowed`. No tiene ningún poder sobre las rondas creadas, sus fondos ni el sorteo.
///      - Coordinador de VRF (`vrfCoordinator`, immutable): el único que puede llamar a `rawFulfillRandomWords`.
///        Es inmutable a propósito: si se pudiera cambiar, quien lo cambia podría entregar un número "aleatorio"
///        elegido por él y arreglar el sorteo.
///      - Rondas creadas por esta factory (`isRonda`): las únicas que pueden llamar a `requestDraw`.
///      - Cualquier cuenta: puede crear rondas con un token habilitado y queda como `organizer` de esa ronda.
///      La factory es el único consumidor de la suscripción de VRF, así no hay que registrar cada ronda nueva en ella.
///      La lista blanca de tokens evita rondas con tokens fee-on-transfer, rebasing o maliciosos, que romperían
///      la contabilidad de `TrustRonda` (que asume que llega exactamente el monto transferido).
contract TrustRondaFactory is Ownable, ITrustRondaDrawer {
    // ─────────────────────────────────────────────────────────────────────
    // Constantes de Chainlink VRF
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Gas máximo del callback de VRF. Alcanza para sortear 12 miembros con margen (medido en los tests: < 225 k).
    uint32 public constant CALLBACK_GAS_LIMIT = 300_000;

    /// @notice Confirmaciones de bloque antes de responder (el mínimo de Sepolia es 3).
    uint16 public constant REQUEST_CONFIRMATIONS = 3;

    /// @notice Cantidad de números aleatorios por sorteo: con uno alcanza para derivar toda la permutación.
    uint32 public constant NUM_WORDS = 1;

    // ─────────────────────────────────────────────────────────────────────
    // Variables de estado inmutables
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Coordinador de Chainlink VRF v2.5 de la red.
    IVRFCoordinatorV2Plus public immutable vrfCoordinator;

    /// @notice Key hash ("gas lane") de VRF: fija el precio máximo de gas del callback.
    bytes32 public immutable keyHash;

    /// @notice Suscripción de VRF que paga los sorteos (esta factory tiene que estar agregada como consumidor).
    uint256 public immutable subscriptionId;

    /// @notice true si la suscripción paga en ETH nativo; false si paga en LINK.
    bool public immutable nativePayment;

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

    /// @notice Pedidos de sorteo pendientes: requestId de VRF → ronda que lo pidió (se borra al responder).
    mapping(uint256 requestId => address ronda) public drawRequests;

    /// @notice Último requestId de VRF de cada ronda (para seguir el pedido en el explorer de VRF).
    mapping(address ronda => uint256 requestId) public drawRequestOf;

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

    /// @notice Una ronda completó su cupo y se le pidió el número aleatorio a Chainlink VRF.
    /// @param ronda Ronda que pidió el sorteo.
    /// @param requestId Identificador del pedido en VRF.
    event DrawRequested(address indexed ronda, uint256 indexed requestId);

    /// @notice Chainlink VRF respondió y se le entregó el número a la ronda.
    /// @param ronda Ronda sorteada.
    /// @param requestId Identificador del pedido en VRF.
    /// @param randomWord Número aleatorio recibido.
    event DrawFulfilled(address indexed ronda, uint256 indexed requestId, uint256 randomWord);

    // ─────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Despliega la factory, configura Chainlink VRF y opcionalmente habilita un primer token.
    /// @dev Después del deploy hay que agregar esta factory como consumidor de la suscripción (`addConsumer`).
    /// @param initialOwner Cuenta que va a poder administrar la lista de tokens (OpenZeppelin v5 lo exige explícito).
    /// @param initialToken Token a habilitar al desplegar; `address(0)` para no habilitar ninguno.
    /// @param vrfCoordinator_ Coordinador de VRF v2.5 de la red (Sepolia: ver docs.chain.link).
    /// @param keyHash_ Key hash ("gas lane") de VRF.
    /// @param subscriptionId_ Id de la suscripción de VRF que paga los sorteos.
    /// @param nativePayment_ true para pagar en ETH nativo, false para pagar en LINK.
    constructor(
        address initialOwner,
        address initialToken,
        address vrfCoordinator_,
        bytes32 keyHash_,
        uint256 subscriptionId_,
        bool nativePayment_
    ) Ownable(initialOwner) {
        if (vrfCoordinator_ == address(0)) revert ZeroCoordinatorAddress();
        vrfCoordinator = IVRFCoordinatorV2Plus(vrfCoordinator_);
        keyHash = keyHash_;
        subscriptionId = subscriptionId_;
        nativePayment = nativePayment_;
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

    /// @notice Pide a Chainlink VRF el número aleatorio para sortear el orden de cobro de la ronda que llama.
    /// @dev Solo rondas creadas por esta factory: así nadie puede gastar el saldo de la suscripción. La llama
    ///      `TrustRonda.join()` cuando se completa el cupo. El requestId se guarda después de la llamada porque recién
    ///      ahí se conoce; el coordinador es un contrato confiable e inmutable, sin riesgo de reentrancy
    ///      (Slither: reentrancy-benign / reentrancy-events aceptados, ver docs/slither.md).
    function requestDraw() external {
        if (!isRonda[msg.sender]) revert NotRonda(msg.sender);
        uint256 requestId = vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: CALLBACK_GAS_LIMIT,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: nativePayment}))
            })
        );
        drawRequests[requestId] = msg.sender;
        drawRequestOf[msg.sender] = requestId;
        emit DrawRequested(msg.sender, requestId);
    }

    /// @notice Callback de Chainlink VRF: entrega el número aleatorio a la ronda que lo pidió.
    /// @dev Solo el coordinador (`vrfCoordinator`). Es la misma firma que `VRFConsumerBaseV2Plus`, pero con el
    ///      coordinador `immutable`: así el owner no puede cambiarlo y arreglar el sorteo. Un requestId desconocido o
    ///      ya usado se ignora sin revertir. CEI: se borra el pedido antes de llamar a la ronda.
    /// @param requestId Identificador del pedido.
    /// @param randomWords Números aleatorios (se usa el primero).
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external {
        if (msg.sender != address(vrfCoordinator)) {
            revert OnlyCoordinatorCanFulfill(msg.sender, address(vrfCoordinator));
        }
        address ronda = drawRequests[requestId];
        if (ronda == address(0)) return;
        delete drawRequests[requestId];
        emit DrawFulfilled(ronda, requestId, randomWords[0]);
        TrustRonda(ronda).fulfillDraw(randomWords[0]);
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
