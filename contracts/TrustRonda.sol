// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Tipos
// ─────────────────────────────────────────────────────────────────────────────

/// @notice Ciclo de vida de una ronda.
/// @dev Open → Active → Completed, u Open → Cancelled. No hay otras transiciones.
enum RondaStatus {
    Open, //       inscripción abierta: se aceptan miembros con garantía
    Active, //     cupo completo: corren los turnos de aporte y cobro
    Completed, //  todos cobraron su turno: se libera la garantía
    Cancelled //   no se llenó a tiempo o la canceló el organizador: se devuelve la garantía
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom errors
// ─────────────────────────────────────────────────────────────────────────────

/// @notice Se pasó la dirección cero donde se requiere una dirección válida.
error ZeroAddress();

/// @notice El aporte por turno tiene que ser mayor que cero.
error InvalidContribution();

/// @notice La garantía tiene que cubrir al menos un aporte.
/// @param collateral Garantía pedida.
/// @param contribution Aporte por turno.
error InvalidCollateral(uint256 collateral, uint256 contribution);

/// @notice La cantidad de miembros está fuera del rango permitido.
/// @param maxMembers Valor recibido.
error InvalidMemberCount(uint8 maxMembers);

/// @notice Una duración (de turno o de inscripción) está fuera del rango permitido.
/// @param duration Valor recibido, en segundos.
error InvalidDuration(uint64 duration);

/// @notice La operación no está permitida en el estado actual de la ronda.
/// @param expected Estado necesario para la operación.
/// @param actual Estado en el que está la ronda.
error InvalidStatus(RondaStatus expected, RondaStatus actual);

/// @notice La cuenta ya está inscripta en la ronda.
/// @param account Cuenta que intentó inscribirse de nuevo.
error AlreadyMember(address account);

/// @notice La cuenta no es miembro de la ronda.
/// @param account Cuenta que llamó.
error NotMember(address account);

/// @notice El período de inscripción ya venció.
/// @param joinDeadline Timestamp de cierre de la inscripción.
error JoinWindowClosed(uint64 joinDeadline);

/// @notice El miembro ya pagó el aporte de este turno.
/// @param account Miembro que intentó pagar de nuevo.
/// @param round Turno en curso.
error AlreadyPaid(address account, uint8 round);

/// @notice El plazo del turno ya venció; el aporte no se puede pagar tarde.
/// @param deadline Timestamp de vencimiento del turno.
error RoundExpired(uint64 deadline);

/// @notice El turno todavía no se puede cerrar: faltan aportes y no venció el plazo.
/// @param deadline Timestamp a partir del cual se puede cerrar igual.
error RoundStillOpen(uint64 deadline);

/// @notice La cuenta no tiene nada para retirar.
/// @param account Cuenta que llamó.
error NothingToWithdraw(address account);

/// @notice Solo el organizador puede cancelar antes de que venza la inscripción.
/// @param caller Cuenta que intentó cancelar.
/// @param joinDeadline Timestamp a partir del cual cualquiera puede cancelar.
error NotAuthorizedToCancel(address caller, uint64 joinDeadline);

/// @title TrustRonda
/// @author Carlos Binker
/// @notice Ronda de ahorro rotativo (ROSCA, "pasanaku", "tanda") sin intermediario de confianza.
///         N miembros depositan una garantía al inscribirse. En cada turno todos aportan el mismo monto
///         y el pozo lo cobra un miembro distinto, en orden de inscripción. Si alguien no paga a tiempo,
///         su aporte se cubre ejecutando su garantía, así el beneficiario del turno cobra igual.
/// @dev Roles y privilegios:
///      - `organizer`: quien creó la ronda desde la factory. Su ÚNICO privilegio es cancelarla mientras
///        está en `Open`. No puede mover fondos, cambiar parámetros ni el orden de cobro.
///      - Miembros: se inscriben, aportan y retiran lo propio.
///      - Cualquier cuenta: puede cerrar un turno cuando corresponde (`closeRound`) y cancelar una ronda
///        que no se llenó antes de `joinDeadline`. Así la ronda nunca depende de que alguien en particular
///        esté presente (en el roadmap, Chainlink Automation hace de keeper).
///      Seguridad: CEI en todas las funciones, `nonReentrant` en las que transfieren tokens, SafeERC20,
///      pull payments para pozos y garantías, y loops acotados por `MAX_MEMBERS`.
contract TrustRonda is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─────────────────────────────────────────────────────────────────────
    // Tipos internos
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Datos de cada miembro, empaquetados en un solo slot de storage (128 + 8 + 8 + 8 bits).
    /// @param collateral Garantía que le queda depositada.
    /// @param position Turno en el que cobra (0 = primero), igual a su orden de inscripción.
    /// @param defaults Cantidad de turnos que no pagó a tiempo.
    /// @param isMember true si está inscripto.
    struct MemberInfo {
        uint128 collateral;
        uint8 position;
        uint8 defaults;
        bool isMember;
    }

    // ─────────────────────────────────────────────────────────────────────
    // Constantes
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Mínimo de miembros por ronda.
    uint8 public constant MIN_MEMBERS = 2;

    /// @notice Máximo de miembros. Acota el único loop del contrato (`closeRound`) y evita DoS por gas.
    uint8 public constant MAX_MEMBERS = 12;

    /// @notice Duración mínima de un turno y de la inscripción (5 minutos, para poder hacer la demo en testnet).
    uint64 public constant MIN_DURATION = 5 minutes;

    /// @notice Duración máxima de un turno y de la inscripción.
    uint64 public constant MAX_DURATION = 90 days;

    // ─────────────────────────────────────────────────────────────────────
    // Variables de estado inmutables (se fijan en el constructor)
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Token ERC20 en el que se aporta y se cobra (en la demo, tUSD).
    IERC20 public immutable token;

    /// @notice Cuenta que creó la ronda; solo puede cancelarla mientras está en `Open`.
    address public immutable organizer;

    /// @notice Monto que aporta cada miembro en cada turno.
    uint256 public immutable contributionAmount;

    /// @notice Garantía que deposita cada miembro al inscribirse.
    uint256 public immutable collateralAmount;

    /// @notice Duración de cada turno, en segundos.
    uint64 public immutable roundDuration;

    /// @notice Timestamp límite para completar el cupo; después cualquiera puede cancelar.
    uint64 public immutable joinDeadline;

    /// @notice Cantidad de miembros que completan el cupo (y cantidad de turnos).
    uint8 public immutable maxMembers;

    // ─────────────────────────────────────────────────────────────────────
    // Variables de estado (las cuatro primeras comparten un slot: 8 + 8 + 8 + 64 bits)
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Estado actual de la ronda.
    RondaStatus public status;

    /// @notice Turno en curso (0 a maxMembers - 1). Cuando la ronda termina vale `maxMembers`.
    uint8 public currentRound;

    /// @notice Cuántos miembros ya pagaron el turno en curso.
    uint8 public paidCount;

    /// @notice Timestamp de vencimiento del turno en curso (0 mientras la ronda está en `Open`).
    uint64 public roundDeadline;

    /// @notice Miembros en orden de inscripción; `_members[i]` cobra en el turno `i`.
    address[] private _members;

    /// @notice Datos de cada miembro.
    mapping(address account => MemberInfo info) private _memberInfo;

    /// @notice Registro de aportes: turno → miembro → pagó.
    mapping(uint8 round => mapping(address account => bool paid)) private _hasPaid;

    /// @notice Pozos cobrados y todavía no retirados (pull payment).
    mapping(address account => uint256 amount) private _payouts;

    // ─────────────────────────────────────────────────────────────────────
    // Eventos
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Un miembro se inscribió y depositó su garantía.
    /// @param member Cuenta inscripta.
    /// @param position Turno en el que va a cobrar.
    /// @param collateral Garantía depositada.
    event MemberJoined(address indexed member, uint8 indexed position, uint256 collateral);

    /// @notice Se completó el cupo y arrancó el primer turno.
    /// @param firstDeadline Vencimiento del primer turno.
    event RondaStarted(uint64 firstDeadline);

    /// @notice Un miembro pagó su aporte del turno.
    /// @param member Cuenta que pagó.
    /// @param round Turno pagado.
    /// @param amount Monto aportado.
    event ContributionMade(address indexed member, uint8 indexed round, uint256 amount);

    /// @notice Se ejecutó la garantía de un miembro que no pagó a tiempo.
    /// @param member Miembro incumplidor.
    /// @param round Turno impago.
    /// @param amount Monto descontado de su garantía.
    event CollateralSlashed(address indexed member, uint8 indexed round, uint256 amount);

    /// @notice Se cerró un turno y su pozo quedó acreditado al beneficiario.
    /// @param round Turno cerrado.
    /// @param beneficiary Miembro que cobra el pozo.
    /// @param pot Monto acreditado (aportes más garantías ejecutadas).
    /// @param defaults Cantidad de miembros que no pagaron ese turno.
    event RoundClosed(uint8 indexed round, address indexed beneficiary, uint256 pot, uint8 defaults);

    /// @notice Arrancó un nuevo turno.
    /// @param round Número de turno.
    /// @param deadline Vencimiento del turno.
    event NewRound(uint8 indexed round, uint64 deadline);

    /// @notice Todos los miembros cobraron: la ronda terminó y la garantía restante se puede retirar.
    event RondaCompleted();

    /// @notice La ronda se canceló antes de arrancar.
    /// @param by Cuenta que la canceló.
    event RondaCancelled(address indexed by);

    /// @notice Un miembro retiró fondos.
    /// @param account Cuenta que retiró.
    /// @param payout Parte que corresponde a pozos cobrados.
    /// @param collateral Parte que corresponde a garantía devuelta.
    event Withdrawn(address indexed account, uint256 payout, uint256 collateral);

    // ─────────────────────────────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Exige que la ronda esté en un estado determinado.
    /// @param expected Estado requerido.
    modifier inStatus(RondaStatus expected) {
        _checkStatus(expected);
        _;
    }

    /// @notice Exige que quien llama sea miembro de la ronda.
    modifier onlyMember() {
        _checkMember(msg.sender);
        _;
    }

    // ─────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Crea una ronda en estado `Open`. Normalmente lo llama `TrustRondaFactory`.
    /// @param organizer_ Cuenta organizadora (la que pidió crear la ronda).
    /// @param token_ Token ERC20 de los aportes.
    /// @param contributionAmount_ Aporte por miembro y por turno.
    /// @param collateralAmount_ Garantía por miembro; tiene que ser >= `contributionAmount_`.
    /// @param maxMembers_ Cupo de miembros, entre `MIN_MEMBERS` y `MAX_MEMBERS`.
    /// @param roundDuration_ Duración de cada turno, entre `MIN_DURATION` y `MAX_DURATION`.
    /// @param joinWindow_ Tiempo para completar el cupo, entre `MIN_DURATION` y `MAX_DURATION`.
    constructor(
        address organizer_,
        IERC20 token_,
        uint256 contributionAmount_,
        uint256 collateralAmount_,
        uint8 maxMembers_,
        uint64 roundDuration_,
        uint64 joinWindow_
    ) {
        if (organizer_ == address(0) || address(token_) == address(0)) revert ZeroAddress();
        if (contributionAmount_ == 0) revert InvalidContribution();
        if (collateralAmount_ < contributionAmount_ || collateralAmount_ > type(uint128).max) {
            revert InvalidCollateral(collateralAmount_, contributionAmount_);
        }
        if (maxMembers_ < MIN_MEMBERS || maxMembers_ > MAX_MEMBERS) revert InvalidMemberCount(maxMembers_);
        if (roundDuration_ < MIN_DURATION || roundDuration_ > MAX_DURATION) revert InvalidDuration(roundDuration_);
        if (joinWindow_ < MIN_DURATION || joinWindow_ > MAX_DURATION) revert InvalidDuration(joinWindow_);

        organizer = organizer_;
        token = token_;
        contributionAmount = contributionAmount_;
        collateralAmount = collateralAmount_;
        maxMembers = maxMembers_;
        roundDuration = roundDuration_;
        joinDeadline = uint64(block.timestamp) + joinWindow_;
        // status arranca en Open (valor 0 del enum)
    }

    // ─────────────────────────────────────────────────────────────────────
    // Funciones external que modifican estado
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Se inscribe en la ronda depositando `collateralAmount`. Requiere `approve` previo.
    /// @dev Si con esta inscripción se completa el cupo, la ronda pasa a `Active` y arranca el turno 0.
    ///      CEI: chequeos → registro del miembro y cambio de estado → `safeTransferFrom`.
    function join() external nonReentrant inStatus(RondaStatus.Open) {
        // Checks
        if (block.timestamp > joinDeadline) revert JoinWindowClosed(joinDeadline);
        MemberInfo storage info = _memberInfo[msg.sender];
        if (info.isMember) revert AlreadyMember(msg.sender);

        // Effects
        // casting to 'uint8' is safe because _members.length < maxMembers <= MAX_MEMBERS (12):
        // si el cupo estuviera lleno la ronda ya no estaría en Open
        // forge-lint: disable-next-line(unsafe-typecast)
        uint8 position = uint8(_members.length);
        _members.push(msg.sender);
        info.isMember = true;
        info.position = position;
        // casting to 'uint128' is safe because el constructor valida collateralAmount <= type(uint128).max
        // forge-lint: disable-next-line(unsafe-typecast)
        info.collateral = uint128(collateralAmount);
        emit MemberJoined(msg.sender, position, collateralAmount);

        if (position + 1 == maxMembers) {
            uint64 deadline = uint64(block.timestamp) + roundDuration;
            status = RondaStatus.Active;
            roundDeadline = deadline;
            emit RondaStarted(deadline);
            emit NewRound(0, deadline);
        }

        // Interactions
        token.safeTransferFrom(msg.sender, address(this), collateralAmount);
    }

    /// @notice Paga el aporte del turno en curso. Requiere `approve` previo por `contributionAmount`.
    /// @dev CEI: chequeos → marca el pago y suma `paidCount` → `safeTransferFrom`.
    function contribute() external nonReentrant inStatus(RondaStatus.Active) onlyMember {
        uint8 round = currentRound; // una sola lectura de storage
        uint64 deadline = roundDeadline;

        // Checks
        if (block.timestamp > deadline) revert RoundExpired(deadline);
        if (_hasPaid[round][msg.sender]) revert AlreadyPaid(msg.sender, round);

        // Effects
        _hasPaid[round][msg.sender] = true;
        unchecked {
            // seguro: paidCount < maxMembers <= 12, cada miembro paga una sola vez por turno
            ++paidCount;
        }
        emit ContributionMade(msg.sender, round, contributionAmount);

        // Interactions
        token.safeTransferFrom(msg.sender, address(this), contributionAmount);
    }

    /// @notice Cierra el turno en curso y acredita el pozo al beneficiario. Lo puede llamar cualquiera.
    /// @dev Se puede cerrar si pagaron todos o si venció `roundDeadline`. A cada miembro que no pagó se le
    ///      descuenta el aporte de su garantía (si le alcanza) y ese monto se suma al pozo.
    ///      No hace llamadas externas: el pozo queda en `_payouts` y el beneficiario lo retira con `withdraw`.
    ///      El loop recorre como máximo `MAX_MEMBERS` (12) miembros y solo si hubo impagos.
    function closeRound() external inStatus(RondaStatus.Active) {
        uint8 round = currentRound;
        uint8 paid = paidCount;
        uint8 n = maxMembers;
        uint64 deadline = roundDeadline;

        // Checks
        if (paid < n && block.timestamp <= deadline) revert RoundStillOpen(deadline);

        // Effects
        uint256 amount = contributionAmount;
        uint256 pot = uint256(paid) * amount;
        uint8 defaults;

        if (paid < n) {
            for (uint256 i; i < n;) {
                address member = _members[i];
                if (!_hasPaid[round][member]) {
                    MemberInfo storage info = _memberInfo[member];
                    uint256 available = info.collateral;
                    uint256 slashed = available < amount ? available : amount;
                    unchecked {
                        ++defaults; // <= 12
                        ++info.defaults; // <= 12 turnos
                        // casting to 'uint128' is safe because available - slashed <= available, que ya es uint128
                        // forge-lint: disable-next-line(unsafe-typecast)
                        info.collateral = uint128(available - slashed);
                    }
                    pot += slashed;
                    emit CollateralSlashed(member, round, slashed);
                }
                unchecked {
                    ++i;
                }
            }
        }

        address beneficiary = _members[round];
        _payouts[beneficiary] += pot;
        emit RoundClosed(round, beneficiary, pot, defaults);

        unchecked {
            ++round; // <= 12
        }
        currentRound = round;
        paidCount = 0;

        if (round == n) {
            status = RondaStatus.Completed;
            roundDeadline = 0;
            emit RondaCompleted();
        } else {
            uint64 nextDeadline = uint64(block.timestamp) + roundDuration;
            roundDeadline = nextDeadline;
            emit NewRound(round, nextDeadline);
        }
    }

    /// @notice Cancela la ronda mientras está en `Open`.
    /// @dev El organizador puede cancelar en cualquier momento de la inscripción; cualquier otra cuenta,
    ///      solo después de `joinDeadline`, para que la garantía de los inscriptos nunca quede trabada.
    function cancel() external inStatus(RondaStatus.Open) {
        if (msg.sender != organizer && block.timestamp <= joinDeadline) {
            revert NotAuthorizedToCancel(msg.sender, joinDeadline);
        }
        status = RondaStatus.Cancelled;
        emit RondaCancelled(msg.sender);
    }

    /// @notice Retira los pozos cobrados y, si la ronda terminó o se canceló, la garantía restante.
    /// @dev Pull payment + CEI: se ponen en cero los saldos antes de `safeTransfer`, y además `nonReentrant`.
    function withdraw() external nonReentrant {
        // Checks
        (uint256 payout, uint256 collateral) = _withdrawable(msg.sender);
        if (payout + collateral == 0) revert NothingToWithdraw(msg.sender);

        // Effects
        if (payout != 0) _payouts[msg.sender] = 0;
        if (collateral != 0) _memberInfo[msg.sender].collateral = 0;
        emit Withdrawn(msg.sender, payout, collateral);

        // Interactions
        token.safeTransfer(msg.sender, payout + collateral);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Funciones external view
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Devuelve los miembros en orden de cobro.
    /// @return Lista de miembros (como máximo `MAX_MEMBERS`, así que no hay riesgo de DoS por tamaño).
    function getMembers() external view returns (address[] memory) {
        return _members;
    }

    /// @notice Cantidad de miembros inscriptos.
    /// @return Cantidad actual.
    function memberCount() external view returns (uint256) {
        return _members.length;
    }

    /// @notice Datos de un miembro.
    /// @param account Cuenta a consultar.
    /// @return info Garantía restante, turno de cobro, cantidad de impagos y si es miembro.
    function getMemberInfo(address account) external view returns (MemberInfo memory info) {
        return _memberInfo[account];
    }

    /// @notice Indica si un miembro pagó un turno.
    /// @param round Turno.
    /// @param account Miembro.
    /// @return true si pagó.
    function hasPaid(uint8 round, address account) external view returns (bool) {
        return _hasPaid[round][account];
    }

    /// @notice Beneficiario del turno en curso.
    /// @dev Revierte si la ronda no está `Active`.
    /// @return Dirección que cobra el turno actual.
    function currentBeneficiary() external view inStatus(RondaStatus.Active) returns (address) {
        return _members[currentRound];
    }

    /// @notice Lo que una cuenta puede retirar ahora.
    /// @param account Cuenta a consultar.
    /// @return payout Pozos cobrados pendientes.
    /// @return collateral Garantía retirable (solo si la ronda está `Completed` o `Cancelled`).
    function withdrawable(address account) external view returns (uint256 payout, uint256 collateral) {
        return _withdrawable(account);
    }

    /// @notice Pozo que se acredita al cerrar un turno en el que pagan todos.
    /// @return Monto del pozo completo.
    function fullPot() external view returns (uint256) {
        return contributionAmount * maxMembers;
    }

    // ─────────────────────────────────────────────────────────────────────
    // Funciones internas
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Revierte si la ronda no está en el estado esperado.
    /// @dev La lógica del modifier vive en una función para no duplicar bytecode en cada uso.
    /// @param expected Estado requerido.
    function _checkStatus(RondaStatus expected) internal view {
        RondaStatus actual = status;
        if (actual != expected) revert InvalidStatus(expected, actual);
    }

    /// @notice Revierte si `account` no es miembro.
    /// @param account Cuenta a validar.
    function _checkMember(address account) internal view {
        if (!_memberInfo[account].isMember) revert NotMember(account);
    }

    /// @notice Calcula lo que una cuenta puede retirar.
    /// @param account Cuenta a consultar.
    /// @return payout Pozos cobrados pendientes.
    /// @return collateral Garantía retirable según el estado de la ronda.
    function _withdrawable(address account) internal view returns (uint256 payout, uint256 collateral) {
        payout = _payouts[account];
        RondaStatus s = status;
        if (s == RondaStatus.Completed || s == RondaStatus.Cancelled) {
            collateral = _memberInfo[account].collateral;
        }
    }
}
