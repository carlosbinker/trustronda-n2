# Análisis estático con Slither

**Herramienta:** Slither 0.11.6 · solc 0.8.24 · 102 detectores
**Alcance:** `contracts/` (MockUSDC, TrustRonda, TrustRondaFactory, ITrustRondaDrawer). Quedan afuera `lib/` (OpenZeppelin, Chainlink, forge-std), `test/` y `script/`, porque no son código propio desplegado. El profesor indicó en la mentoría que lo que viene de OpenZeppelin queda fuera de alcance.

```bash
slither . --filter-paths "lib|test|script" --exclude-dependencies
# formato checklist, como pidió el profesor en la mentoría (clase 20, 0:58:56):
slither . --filter-paths "lib|test|script" --exclude-dependencies --checklist > docs/reports/slither-checklist.md
```

Salidas: [`reports/slither.txt`](reports/slither.txt) · [`reports/slither-checklist.md`](reports/slither-checklist.md) · [`reports/slither.json`](reports/slither.json)

## Resumen

| # | Detector | Severidad | Dónde | Estado |
|---|---|---|---|---|
| 1 | `uninitialized-local` | Medium | `TrustRonda.closeRound()` → `defaults` | **Corregido** |
| 2 | `unused-return` | Medium | `TrustRonda.join()` ignoraba el retorno de `requestDraw()` | **Corregido** |
| 3 | `reentrancy-benign` | Low | `TrustRondaFactory.requestDraw()` | Aceptado (justificado) |
| 4 | `reentrancy-events` | Low | `TrustRondaFactory.requestDraw()` | Aceptado (justificado) |
| 5 a 9 | `timestamp` | Low | `join`, `contribute`, `closeRound`, `cancel` y `MockUSDC.faucet` | Aceptados (justificados) |

Corrida final: **7 findings, todos Low y aceptados**. No queda ningún High ni Medium.

## 1. `uninitialized-local`: corregido
`uint8 defaults;` dentro de `closeRound()` se declaraba sin inicializar. En Solidity vale 0 por defecto, así que no era un bug, pero se inicializó explícitamente (`uint8 defaults = 0;`) para que la intención quede clara.

## 2. `unused-return`: corregido
Cuando se agregó Chainlink VRF, `requestDraw()` devolvía el `requestId` y la ronda no lo usaba. Ignorar un retorno puede esconder un error. Se cambió la interfaz: `requestDraw()` no devuelve nada, y el `requestId` queda registrado en la factory (`drawRequestOf(ronda)`) y en el evento `DrawRequested`.

## 3 y 4. `reentrancy-benign` / `reentrancy-events` en `requestDraw()`: aceptados
Slither avisa que, después de llamar a `vrfCoordinator.requestRandomWords(...)`, se escriben `drawRequests` / `drawRequestOf` y se emite `DrawRequested`.

**Por qué se aceptan:**
- El `requestId` **lo genera el coordinador** y recién se conoce cuando vuelve la llamada. No hay forma de escribirlo antes.
- El coordinador es el contrato oficial de Chainlink VRF v2.5, y su dirección es `immutable` en la factory: no lo puede cambiar nadie, ni el owner. No es un contrato arbitrario que pueda reentrar.
- Aunque reentrara, `requestDraw` solo lo pueden llamar rondas creadas por la factory (`isRonda`), y una ronda solo lo llama una vez, desde `join()`, protegido con `nonReentrant`.
- La respuesta de VRF llega en **otra transacción**, varios bloques después. No hay callback dentro de la misma llamada.

## 5 a 9. `timestamp`: aceptados
Slither avisa que se compara contra `block.timestamp`, porque el proposer del bloque puede correrlo unos segundos.

**Por qué se aceptan:**
- **Se usa para plazos, no para aleatoriedad.** Los vencimientos (inscripción, turno, timeout del sorteo y cooldown del faucet) son plazos de calendario. La aleatoriedad, que es donde `block.timestamp` sí sería peligroso, la da Chainlink VRF.
- **El margen de manipulación no pesa frente a los plazos.** Los slots de Ethereum son de 12 s; los plazos mínimos del contrato son de 5 minutos y los típicos, de días.
- **Ningún monto depende del tiempo.** El tiempo solo habilita o bloquea transiciones.
- **Peor caso:** un proposer que además es miembro gana unos segundos para pagar, que es justamente lo que el contrato espera que haga.

## Revisión manual complementaria

| Riesgo | Mitigación en el código |
|---|---|
| Reentrancy | CEI en `join`, `contribute` y `withdraw`, más `nonReentrant`. `closeRound` no hace llamadas externas. En `rawFulfillRandomWords` se borra el pedido antes de llamar a la ronda. |
| Sorteo manipulable | Chainlink VRF con prueba verificada on-chain. Coordinador `immutable`, sin `setCoordinator`: por eso no se hereda `VRFConsumerBaseV2Plus`, que le daría al owner la posibilidad de cambiarlo y arreglar el sorteo. Callback solo del coordinador y entrega solo de la factory. |
| VRF que no responde | `DRAW_TIMEOUT = 1 día`: después, cualquiera cancela y todos recuperan la garantía. |
| Callback de VRF que revierte | `fulfillDraw` no revierte si la ronda ya no está en `Drawing`, y un requestId desconocido se ignora. El callback medido con 12 miembros usa 372 k de gas con las reglas de Glamsterdam (`make test-amsterdam`), contra un límite de 500 k. |
| Gasto de la suscripción por terceros | `requestDraw` solo lo pueden llamar rondas creadas por la factory. |
| Tokens raros (fee-on-transfer, rebasing) | Lista blanca de tokens en la factory (`setTokenAllowed`, solo el owner). |
| Transferencias ERC20 que no revierten | `SafeERC20` (`safeTransfer` / `safeTransferFrom`). |
| DoS por loops | Loops acotados por `MAX_MEMBERS = 12`; `getRondas` paginado. |
| DoS por un receptor que revierte o está en blacklist | Pull payments: cada uno retira lo suyo con `withdraw()`. Nadie le transfiere fondos a otro durante el flujo, así que una dirección bloqueada no traba la ronda (punto que remarcó el profesor en la mentoría). |
| Control de acceso | El organizador solo puede cancelar en `Open`; el owner de la factory solo maneja la lista blanca. Ninguno puede mover fondos ni tocar el sorteo. |
| Fondos trabados | Cancelación permisionless después de `joinDeadline` y del timeout de VRF; cierre permisionless de turnos vencidos. |
| Overflow / truncamiento | Solidity 0.8; `unchecked` solo en contadores acotados; casts justificados y validados. |
| `tx.origin`, `delegatecall`, `selfdestruct`, assembly | No se usan. |

Además del análisis estático: 67 tests (incluida la invariante de solvencia exacta y el fuzz de que el sorteo siempre es una permutación) y coverage del 100 %.
