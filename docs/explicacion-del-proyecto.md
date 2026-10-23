# Explicación del proyecto, parte por parte

Este documento recorre todo el código de TrustRonda y explica **qué hace cada parte y por qué está hecha así**, con el vocabulario del curso. Sirve para estudiar el proyecto, para responder preguntas en la corrección y como base del video.

---

## Parte 0: Cómo está organizado el monorepo

Un solo repositorio contiene los contratos (Foundry) y el frontend (React):

| Carpeta | Qué hay | Herramienta |
|---|---|---|
| `contracts/` | Los 3 contratos Solidity | `forge build` |
| `test/` | 58 tests | `forge test`, `forge coverage` |
| `script/` | Deploy, demo y verificación | `forge script`, `cast` |
| `deployments/` | Direcciones por red (JSON) | lo escribe `Deploy.s.sol` |
| `frontend/` | La dApp | `npm run dev` |
| `docs/` | Whitepaper, Slither, esta guía, guion | — |
| `lib/` | OpenZeppelin v5.1.0 y forge-std como submódulos git | `git submodule` |

`foundry.toml` define `src = "contracts"` porque el enunciado pide la carpeta `/contracts` (Foundry usa `src/` por defecto), fija `solc 0.8.24` con optimizer en 200 runs y lee el RPC y la API key de Etherscan **desde variables de entorno**. Así no hay secretos en el repo.

---

## Parte 1: `MockUSDC.sol`, el token de prueba

**Para qué:** las rondas se hacen en stablecoin. En Sepolia no hay un USDC con faucet confiable, así que creamos uno.

```solidity
contract MockUSDC is ERC20 {
    uint256 public constant FAUCET_AMOUNT = 1_000e6;
    uint256 public constant FAUCET_COOLDOWN = 1 days;
    mapping(address account => uint256 timestamp) public lastFaucetClaim;
```

- **Hereda de `ERC20` de OpenZeppelin**: no reimplementamos un estándar auditado.
- **`constant`**: los valores fijos van en el bytecode, no en storage (gas).
- **Mapping con nombres** (`account => timestamp`): sintaxis de Solidity 0.8.18+ que documenta qué es cada cosa.
- **6 decimales** (`decimals()` override, `pure`): igual que USDC. `1_000e6` = 1.000 tUSD.

```solidity
function faucet() external {
    uint256 last = lastFaucetClaim[msg.sender];                 // 1 lectura de storage
    if (last != 0 && block.timestamp < last + FAUCET_COOLDOWN) {
        revert FaucetCooldown(last + FAUCET_COOLDOWN);          // custom error con parámetro
    }
    lastFaucetClaim[msg.sender] = block.timestamp;              // effect
    _mint(msg.sender, FAUCET_AMOUNT);
    emit FaucetClaimed(msg.sender, FAUCET_AMOUNT);
}
```

**CEI:** primero el chequeo, después el cambio de estado, al final la emisión. El custom error devuelve **cuándo** se puede volver a pedir, y el frontend lo usa para mostrar el mensaje. No hay owner: nadie puede emitir tokens por fuera del faucet.

---

## Parte 2: `TrustRonda.sol`, el contrato principal

### 2.1 Orden del archivo (estándar de la clase 3)
Licencia → pragma → imports → **tipos y errores a nivel de archivo** → contrato con: struct, constantes, immutables, variables de estado, eventos, modifiers, constructor, funciones `external` que escriben, `external view`, `internal`.

### 2.2 La máquina de estados
```solidity
enum RondaStatus { Open, Active, Completed, Cancelled }
```
Toda función empieza validando el estado con el modifier `inStatus(...)`. Si no coincide, revierte con `InvalidStatus(expected, actual)`, que dice qué se esperaba y qué había: muy útil para depurar.

### 2.3 Custom errors (14)
Van definidos **fuera del contrato**, a nivel de archivo, como indica el orden de la clase 3. Cuestan menos gas que un `require` con string y llevan parámetros:
`RoundStillOpen(uint64 deadline)` le dice al usuario **desde cuándo** se va a poder cerrar el turno.

### 2.4 Variables: `constant`, `immutable` y storage empaquetado
```solidity
uint8 public constant MAX_MEMBERS = 12;          // límite fijo → constant
IERC20 public immutable token;                    // se fija en el constructor → immutable
uint256 public immutable contributionAmount;
...
RondaStatus public status;   // ┐
uint8 public currentRound;   // │ las 4 en UN slot de 32 bytes
uint8 public paidCount;      // │ (8 + 8 + 8 + 64 = 88 bits)
uint64 public roundDeadline; // ┘
```
- `immutable`: los parámetros de la ronda no cambian nunca. Esto da **garantía de reglas fijas**, que es el punto del producto, y lecturas baratas.
- **Empaquetado:** cuando se cierra un turno, las cuatro variables se actualizan escribiendo un solo slot.
- `uint64` alcanza para timestamps hasta el año ~584 mil millones.

```solidity
struct MemberInfo { uint128 collateral; uint8 position; uint8 defaults; bool isMember; } // 1 slot
address[] private _members;                                       // orden de cobro
mapping(address => MemberInfo) private _memberInfo;
mapping(uint8 => mapping(address => bool)) private _hasPaid;      // turno → miembro → pagó
mapping(address => uint256) private _payouts;                     // pozos por retirar
```
El estado es `private` con getters `view` (recomendación de la clase 3: se controla el acceso).

### 2.5 Eventos (9)
`MemberJoined`, `RondaStarted`, `ContributionMade`, `CollateralSlashed`, `RoundClosed`, `NewRound`, `RondaCompleted`, `RondaCancelled` y `Withdrawn`. Las direcciones y los turnos van `indexed` para poder filtrarlos. **El frontend arma el historial on-chain solo con estos eventos.**

### 2.6 Constructor: validar todo una sola vez
Valida direcciones no nulas, aporte > 0, garantía ≥ aporte (y que entre en `uint128`), cupo entre 2 y 12, y duraciones entre 5 minutos y 90 días. Si algo falla, revierte con un error específico. La factory **no duplica** estas validaciones: si el constructor revierte, revierte toda la transacción de `createRonda`.

### 2.7 `join()`: inscripción con garantía
```solidity
function join() external nonReentrant inStatus(RondaStatus.Open) {
    // Checks
    if (block.timestamp > joinDeadline) revert JoinWindowClosed(joinDeadline);
    MemberInfo storage info = _memberInfo[msg.sender];        // puntero a storage: se modifica en el lugar
    if (info.isMember) revert AlreadyMember(msg.sender);
    // Effects
    uint8 position = uint8(_members.length);
    _members.push(msg.sender);
    info.isMember = true; info.position = position; info.collateral = uint128(collateralAmount);
    emit MemberJoined(msg.sender, position, collateralAmount);
    if (position + 1 == maxMembers) { status = Active; roundDeadline = now + roundDuration; ... }
    // Interactions
    token.safeTransferFrom(msg.sender, address(this), collateralAmount);
}
```
- **CEI estricto:** la transferencia, que es la llamada externa, va **al final**.
- **`nonReentrant`**: segunda capa, por si el token tuviera hooks.
- **`safeTransferFrom` (SafeERC20)**: revierte aunque el token devuelva `false` en vez de revertir.
- **`storage` vs `memory`**: `MemberInfo storage info` apunta al storage real, así que asignarle valores lo modifica sin copiar.
- **Arranque automático:** el último inscripto pone la ronda en `Active`. No hace falta que nadie más lo active.

### 2.8 `contribute()`: aporte del turno
Cachea `currentRound` y `roundDeadline` en variables locales (una lectura de storage cada una), chequea plazo y doble pago, marca `_hasPaid` e incrementa `paidCount` dentro de `unchecked`. Es seguro porque nunca supera 12, y ahorra el chequeo de overflow. La transferencia va al final.

### 2.9 `closeRound()`: el corazón del protocolo
```solidity
if (paid < n && block.timestamp <= deadline) revert RoundStillOpen(deadline);
uint256 pot = paid * amount;
if (paid < n) {                       // solo se recorre si hubo impagos
    for (i < n) {                     // n ≤ 12 → sin DoS por gas
        if (!_hasPaid[round][member]) {
            slashed = min(collateral, amount);
            info.collateral -= slashed; ++info.defaults;
            pot += slashed;
            emit CollateralSlashed(member, round, slashed);
        }
    }
}
_payouts[beneficiary] += pot;         // acreditar (pull), NO transferir
```
- Se puede cerrar **antes** del vencimiento si pagaron todos (camino rápido de la demo) o **después**, aunque falten pagos.
- **Lo puede llamar cualquiera.** No depende de una persona, y en el roadmap lo llama Chainlink Automation.
- **No transfiere nada.** Si lo hiciera y el beneficiario fuera un contrato que revierte, bloquearía la ronda entera. Con **pull payments** cada uno retira lo suyo.
- Al cerrar el último turno pasa a `Completed` y se libera la garantía restante.

### 2.10 `withdraw()`: pull payment
Calcula lo retirable, **pone los saldos en cero antes de transferir** (effects antes que interactions) y después hace `safeTransfer`. Un segundo `withdraw` revierte con `NothingToWithdraw`: hay un test que lo prueba.

### 2.11 `cancel()`: que la garantía nunca quede trabada
El organizador cancela en cualquier momento de la inscripción. Después de `joinDeadline`, **cualquiera** puede cancelar. Así, si el organizador desaparece, los inscriptos recuperan su garantía igual.

### 2.12 Modifiers con la lógica en funciones internas
```solidity
modifier inStatus(RondaStatus expected) { _checkStatus(expected); _; }
```
Un modifier se "pega" en cada función que lo usa. Moviendo la lógica a `_checkStatus`, el bytecode no se duplica (sugerencia de `forge lint`).

---

## Parte 3: `TrustRondaFactory.sol`, la interacción entre contratos

```solidity
function createRonda(...) external returns (address ronda) {
    if (!isTokenAllowed[token]) revert TokenNotAllowed(token);
    TrustRonda newRonda = new TrustRonda(msg.sender, IERC20(token), ...);   // ← contrato crea contrato
    _rondas.push(address(newRonda)); isRonda[address(newRonda)] = true;
    emit RondaCreated(address(newRonda), msg.sender, token, ...);
}
```
- **`new`** despliega un contrato desde otro: es la interacción entre contratos que pide el checklist. Además, `TrustRonda` interactúa con el ERC20 externo.
- **`msg.sender` pasa como organizador**: si no, el organizador sería la factory.
- **`Ownable(initialOwner)`**: en OpenZeppelin v5 el owner se pasa explícito al constructor. Su **único** privilegio es `setTokenAllowed`.
- **Lista blanca:** evita que alguien cree una ronda con un token que cobra comisión al transferir. En ese caso llegaría menos de lo que el contrato cree, y la contabilidad quedaría insolvente.
- **`getRondas(offset, limit)` paginado**: devolver un array entero sin límite puede quedarse sin gas cuando crece. El cálculo de `end` está hecho para que `offset + limit` no haga overflow.

---

## Parte 4: Los tests

### 4.1 `BaseTest.sol`
`setUp()` corre antes de **cada** test: despliega tUSD y la factory y fondea a `alice`, `bob`, `carol` y `outsider` con el faucet (`vm.prank`). Los helpers `_join`, `_contribute` y `_createActiveRonda` evitan repetir código.

### 4.2 Unitarios e integración (`TrustRonda.t.sol`, `TrustRondaFactory.t.sol`, `MockUSDC.t.sol`)
- **Flujo completo** (`test_FullCycle_AllPay_EveryoneEndsEven`): 3 miembros y 3 turnos. Al final cada uno tiene exactamente lo que tenía y el contrato queda en 0.
- **Un test por cada revert**, con el selector y los parámetros exactos:
  `vm.expectRevert(abi.encodeWithSelector(AlreadyPaid.selector, alice, uint8(0)));`
- **Eventos** con `vm.expectEmit(true, true, false, true, address(ronda))`.
- **Tiempo** con `vm.warp(deadline + 1)` para probar impagos y vencimientos.
- **Detalle aprendido:** un getter usado como argumento de `expectRevert` se lee **antes** de `vm.prank`, porque el prank lo consume la primera llamada.

### 4.3 Fuzz (`TrustRonda.fuzz.t.sol`)
`testFuzz_MoneyIsConserved` recibe aporte, garantía, cupo y una máscara de bits que decide quién paga en cada turno. Se acotan con `bound` (más eficiente que `vm.assume`) y `deal` les da saldo. **Propiedad:** al final, la suma de saldos de los miembros es igual a la inicial y el contrato queda en 0. Corre 512 veces con valores distintos.

### 4.4 Invariant testing (`test/invariant/`)
- El **handler** expone acciones válidas y acotadas. El fuzzer las llama en secuencias aleatorias de 64 llamadas, 128 veces.
- **`invariant_SolvencyExact`** compara el saldo real del token con la contabilidad interna (pozos + garantías + aportes del turno abierto). Es la invariante útil que pide el apunte de la clase 10: compara dos magnitudes que podrían desalinearse, no algo trivial como "balance ≥ 0".
- `afterInvariant()` imprime cuántas veces se ejecutó cada acción, para comprobar que el fuzzer llegó a rondas completas.

### 4.5 Coverage
`forge coverage --no-match-coverage "(script|test)"` da **100 % en las cuatro métricas**. El checklist pide > 40 %.

---

## Parte 5: Slither
Una corrida inicial con 6 findings. Se corrigió `uninitialized-local` y se justificaron los 5 `timestamp`: el tiempo se usa para plazos, no para aleatoriedad. Todo está en `docs/slither.md`.

---

## Parte 6: Scripts
- **`Deploy.s.sol`**: `vm.startBroadcast(pk)` firma con la key del `.env`. Despliega el token y la factory, y `vm.writeJson` guarda las direcciones en `deployments/<chainId>.json`. Con `--verify`, forge verifica en Etherscan.
- **`Demo.s.sol`**: juega una ronda completa con dos wallets (`PRIVATE_KEY`, `PRIVATE_KEY_2`) y deja **transacciones reales** para el README.
- **`verify-ronda.sh`**: las rondas creadas por la factory no las verifica `--verify`. El script reconstruye los argumentos del constructor leyendo los getters con `cast call` y el bloque del evento `RondaCreated`, y llama a `forge verify-contract`.
- **`Makefile`**: atajos (`make test`, `make deploy`…).

---

## Parte 7: El frontend
| Archivo | Responsabilidad |
|---|---|
| `config.ts` | wagmi: red (Sepolia), conector `injected` (MetaMask), direcciones por `VITE_*` |
| `abi/*.ts` | ABIs exportados de `out/` con `as const`, así TypeScript conoce cada función y sus tipos |
| `lib/useTx.ts` | Manda `approve` + acción en secuencia, espera el receipt y guarda el hash |
| `lib/errors.ts` | Decodifica el custom error del revert y lo traduce ("Ya pagaste el aporte de este turno.") |
| `RondaDetail.tsx` | Lee el estado con `useReadContracts` (multicall) y muestra **solo las acciones válidas** según estado, cuenta y tiempo |
| `Wheel.tsx` | La ronda como círculo de lugares: ya cobró, turno actual, pagó, impago |
| `Activity.tsx` | `getContractEvents` → historial con link a Etherscan (evidencia on-chain) |

**Por qué `approve` + acción:** un contrato no puede sacar tokens de tu wallet sin permiso. `approve` autoriza a la ronda a mover exactamente el monto, y después `join` o `contribute` hacen el `transferFrom`. Si el allowance ya alcanza, el frontend se saltea el `approve`.

Se probó de punta a punta con Playwright contra anvil, con dos cuentas.

---

## Preguntas probables en la corrección (y respuestas cortas)

- **¿Por qué no transferís el pozo en `closeRound`?** Por pull payments: si el beneficiario fuera un contrato que revierte, bloquearía la ronda. Además, `closeRound` queda sin llamadas externas.
- **¿Dónde está la interacción entre contratos?** La factory despliega `TrustRonda` con `new`, y `TrustRonda` llama al ERC20 con SafeERC20.
- **¿Por qué no usaste un proxy?** Porque el valor del producto es que las reglas no cambien a mitad de la ronda. Un proxy le daría a alguien el poder de cambiarlas.
- **¿Qué pasa si nadie cierra el turno?** Lo puede cerrar cualquiera, y el beneficiario tiene todo el incentivo. En la fase 2 lo hace Chainlink Automation.
- **¿Por qué el orden es por inscripción y no VRF?** Para priorizar un flujo completo y robusto en el MVP, como pidió el profesor. VRF está en el roadmap, con el riesgo (front-running del `join`) documentado.
- **¿Es seguro el `unchecked`?** Sí: solo envuelve contadores que nunca superan 12 y una resta en la que `slashed ≤ available` está garantizado.
