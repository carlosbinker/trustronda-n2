# Análisis estático con Slither

**Herramienta:** Slither 0.11.6 · solc 0.8.24 · 102 detectores
**Alcance:** `contracts/` (MockUSDC, TrustRonda, TrustRondaFactory). Se excluyen `lib/` (OpenZeppelin, forge-std), `test/` y `script/` porque no son código propio desplegado.

```bash
slither . --filter-paths "lib|test|script" --exclude-dependencies
```

Salida completa: [`reports/slither.txt`](reports/slither.txt) · JSON: [`reports/slither.json`](reports/slither.json)

## Resumen

| # | Detector | Severidad | Dónde | Estado |
|---|---|---|---|---|
| 1 | `uninitialized-local` | Medium | `TrustRonda.closeRound()` → `defaults` | **Corregido** |
| 2 | `timestamp` | Low | `TrustRonda.join()` | Aceptado (justificado) |
| 3 | `timestamp` | Low | `TrustRonda.contribute()` | Aceptado (justificado) |
| 4 | `timestamp` | Low | `TrustRonda.closeRound()` | Aceptado (justificado) |
| 5 | `timestamp` | Low | `TrustRonda.cancel()` | Aceptado (justificado) |
| 6 | `timestamp` | Low | `MockUSDC.faucet()` | Aceptado (justificado) |

Primera corrida: 6 findings. Después de la corrección: **5 findings, todos `timestamp` y aceptados**. No quedan findings de severidad High ni Medium.

## 1. `uninitialized-local`: corregido

`uint8 defaults;` dentro de `closeRound()` se declaraba sin inicializar. En Solidity vale 0 por defecto, así que no era un bug, pero Slither lo marca porque una variable sin inicializar suele ser un descuido. Se inicializó explícitamente (`uint8 defaults = 0;`) para que la intención quede clara y el reporte, limpio.

## 2 a 6. `timestamp`: aceptados

Slither avisa que se compara contra `block.timestamp`, porque el proposer del bloque puede correrlo unos segundos.

**Por qué se aceptan:**

- **Es la herramienta correcta para un plazo.** Los vencimientos de una ronda (inscripción, turno, cooldown del faucet) son plazos de calendario, no fuentes de aleatoriedad. El apunte de la clase 14 desaconseja usar `block.timestamp` para **aleatoriedad** (para eso está VRF), no para plazos.
- **El margen de manipulación es despreciable frente a los plazos.** Desde The Merge, en Ethereum los slots son fijos de 12 s y el timestamp no se puede mover de forma arbitraria. Los plazos mínimos del contrato son `MIN_DURATION = 5 minutes` y los típicos son días. Correr el reloj unos segundos no cambia quién llega a tiempo de forma significativa.
- **Ningún monto depende del timestamp.** El tiempo solo habilita o bloquea transiciones: pagar, cerrar o cancelar. Ni el pozo ni la garantía se calculan con él.
- **Peor caso analizado:** un proposer que además es miembro podría intentar que su aporte entre justo en el borde de `roundDeadline`. Ganaría unos segundos para pagar, que es exactamente lo que el contrato espera que haga (pagar). No puede evitar que se le ejecute la garantía si no paga.
- **`MockUSDC.faucet()`:** el cooldown es solo una medida anti-spam de un token de prueba sin valor.

## Revisión manual complementaria (más allá de Slither)

| Riesgo | Mitigación en el código |
|---|---|
| Reentrancy | CEI en `join`, `contribute` y `withdraw`, más `nonReentrant`. `closeRound` no hace llamadas externas. |
| Tokens raros (fee-on-transfer, rebasing) | Lista blanca de tokens en la factory (`setTokenAllowed`, solo el owner). |
| Transferencias ERC20 que no revierten | `SafeERC20` (`safeTransfer` / `safeTransferFrom`). |
| DoS por loops | Un único loop en `closeRound`, acotado por `MAX_MEMBERS = 12`; `getRondas` paginado. |
| DoS por un receptor que revierte | Pull payments: cada uno retira lo suyo con `withdraw()`, nadie le "empuja" fondos a otro. |
| Control de acceso | El organizador solo puede cancelar en `Open`; el owner de la factory solo maneja la lista blanca. Ninguno puede mover fondos. |
| Fondos trabados | Cualquiera puede cancelar una ronda que no se llenó después de `joinDeadline`; cualquiera puede cerrar un turno vencido. |
| Overflow / truncamiento | Solidity 0.8 con chequeo; `unchecked` solo en contadores acotados por 12; casts justificados y validados (`collateralAmount <= type(uint128).max`). |
| `tx.origin`, `delegatecall`, `selfdestruct`, assembly | No se usan. |
| Front-running / MEV | No hay precios ni swaps: el orden de cobro lo fija el orden de inscripción, que es público. Ver limitación en el README. |

Además del análisis estático: 58 tests, incluida la invariante de solvencia exacta (`invariant_SolvencyExact`), y coverage del 100 %.
