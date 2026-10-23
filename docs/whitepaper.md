# TrustRonda — Whitepaper técnico (Nivel 2)

**Ronda de ahorro rotativo on-chain con garantía ejecutable**

Carlos Binker · Ethereum Developer Pack, Nivel 2 (ETH Kipu / Talento Tech) · Octubre 2026
Versión 2.0: refleja el MVP **implementado y desplegado** en Sepolia. La versión 1.0, del Nivel 1, era el diseño conceptual.

---

## Resumen

TrustRonda lleva a Ethereum la ronda de ahorro rotativo (ROSCA): un grupo aporta un monto fijo en cada turno y en cada turno uno de los miembros se lleva el pozo. El contrato reemplaza al organizador como custodio, fija las reglas de forma inmutable y le pide a cada miembro una **garantía** que se ejecuta automáticamente si no paga, para que el beneficiario del turno cobre igual. El MVP consta de tres contratos (`TrustRondaFactory`, `TrustRonda` y `MockUSDC`), tiene 58 tests con coverage del 100 % y análisis con Slither, y se opera desde un frontend en React.

---

## 1. Definición del problema

La ronda, también llamada *tanda*, *pasanaku*, *junta* o *susu*, es uno de los instrumentos de ahorro informal más extendidos del mundo. Sirve a personas con acceso limitado al crédito: el que cobra primero obtiene un préstamo sin interés, y el que cobra último ahorra con disciplina. Sus fallas son estructurales:

1. **Riesgo de custodia.** Un organizador junta el dinero. Puede desaparecer, equivocarse o favorecer a alguien.
2. **Riesgo de contraparte con incentivos desalineados.** Después de cobrar, a un miembro le conviene dejar de pagar: ya obtuvo su pozo y los turnos que quedan son solo costo. Los últimos del orden son los más expuestos.
3. **Reglas que se pueden discutir.** Orden de cobro, montos o qué pasa ante un atraso se acuerdan de palabra y se renegocian sobre la marcha.
4. **Sin registro verificable.** Ante un conflicto, es la palabra de uno contra la del otro.

Estas fallas limitan la ronda a círculos de confianza muy cercanos: familia, compañeros de trabajo.

## 2. Solución

TrustRonda ataca cada falla con una propiedad de la blockchain:

| Falla | Mecanismo en TrustRonda |
|---|---|
| Custodia | Los fondos los retiene el contrato. No existe ninguna función que permita a un tercero, ni al organizador ni al owner de la factory, mover fondos ajenos. |
| Incentivo a dejar de pagar | Garantía depositada al inscribirse. Si un miembro no paga antes del vencimiento, `closeRound` descuenta el aporte de su garantía y lo suma al pozo. |
| Reglas discutibles | Aporte, garantía, cupo y duraciones son `immutable`. El orden de cobro es el orden de inscripción, registrado on-chain. |
| Sin registro | Cada acción emite un evento indexado, auditable en Etherscan y visible en el historial del frontend. |
| Dependencia de una persona | `closeRound` lo puede llamar cualquiera. Una ronda que no se llena se puede cancelar por cualquiera después del plazo, así la garantía nunca queda trabada. |

### 2.1 Por qué blockchain y no una app tradicional
Una app centralizada solucionaría el registro, pero no la custodia ni la inmutabilidad: el operador de la app pasaría a ser el nuevo organizador en el que hay que confiar. El valor de TrustRonda está justamente en que **no hay operador**: las reglas las ejecuta un código público y verificado, y los fondos solo salen hacia quien tiene derecho a ellos.

## 3. Arquitectura implementada

```
Usuario (MetaMask) ──► Frontend React + wagmi/viem
                          │
                          ├─► TrustRondaFactory ──new──► TrustRonda (una por ronda)
                          │        (Ownable)                (ReentrancyGuard, SafeERC20)
                          │                                     │
                          └─► MockUSDC (tUSD) ◄──safeTransfer───┘
```

### 3.1 Contratos

**`TrustRondaFactory`**: despliega cada ronda con `new`, que es la interacción entre contratos del sistema, y la registra en un array con lectura paginada. Mantiene una **lista blanca de tokens** (`setTokenAllowed`, solo el owner) para evitar tokens fee-on-transfer o rebasing, que romperían la contabilidad. El owner no tiene ningún poder sobre las rondas ya creadas.

**`TrustRonda`**: una ronda concreta. Máquina de estados `Open → Active → Completed` (u `Open → Cancelled`).

| Función | Quién | Qué hace |
|---|---|---|
| `join()` | cualquiera, en `Open` | Deposita la garantía; el último del cupo arranca el turno 0 |
| `contribute()` | miembro, en `Active` | Paga el aporte del turno antes del vencimiento |
| `closeRound()` | cualquiera, en `Active` | Si pagaron todos o venció el plazo: ejecuta las garantías de los que no pagaron, acredita el pozo al beneficiario y avanza el turno |
| `withdraw()` | quien tenga saldo | Pull payment del pozo y, al terminar o cancelar, de la garantía |
| `cancel()` | organizador (o cualquiera tras `joinDeadline`), en `Open` | Cancela una ronda que no arrancó |

**`MockUSDC`**: ERC20 de 6 decimales con faucet de 1.000 tUSD por día y cuenta. Existe solo para que la demo funcione en testnet.

### 3.2 Modelo de datos y gas
- Los siete parámetros de la ronda son `immutable`: se guardan en el bytecode y su lectura cuesta lo mismo que una constante.
- `status`, `currentRound`, `paidCount` y `roundDeadline` comparten **un slot** (8 + 8 + 8 + 64 bits). Cada transición escribe un solo slot.
- `MemberInfo { uint128 collateral; uint8 position; uint8 defaults; bool isMember; }` ocupa **un slot** por miembro.
- `closeRound` cachea en memoria las variables de storage y solo recorre a los miembros cuando hay impagos. El cupo máximo de 12 acota el peor caso (unos 200 k de gas medidos).

### 3.3 Contabilidad y solvencia
En todo momento se cumple, y se verifica con invariant testing:

```
balance(tUSD, ronda) = Σ pozos acreditados sin retirar
                     + Σ garantías restantes
                     + (aportes ya pagados del turno en curso)
```

Cuando se cierra un turno, los aportes del turno pasan a "pozo acreditado" del beneficiario, junto con lo ejecutado de las garantías. El dinero cambia de categoría, pero el total no se crea ni se destruye.

## 4. Seguridad y riesgos

### 4.1 Medidas implementadas
| Vector | Mitigación |
|---|---|
| Reentrancy | CEI en todas las funciones que transfieren, más `nonReentrant`. `closeRound` no hace llamadas externas. |
| Tokens ERC20 no estándar | `SafeERC20` y lista blanca de tokens en la factory |
| DoS por receptor malicioso | Pull payments: nadie le "empuja" fondos a otro |
| DoS por gas | Un único loop, acotado a 12 iteraciones; registro paginado |
| Abuso de privilegios | Organizador: solo cancelar en `Open`. Owner: solo la lista blanca futura. Sin funciones de rescate ni pausas que permitan tomar fondos. |
| Fondos trabados | Cancelación permisionless después de `joinDeadline`; cierre permisionless de turnos vencidos |
| Overflow / truncamiento | Solidity 0.8; `unchecked` solo en contadores acotados; `collateralAmount ≤ type(uint128).max` validado en el constructor |
| Manipulación de `block.timestamp` | Solo se usa para plazos (mínimo 5 minutos). Ningún monto depende del tiempo (ver `docs/slither.md`). |

### 4.2 Verificación
- **58 tests** (unitarios, de integración, fuzz con 512 corridas e invariantes con 128 × 64 llamadas). Coverage del 100 % en líneas, statements, branches y funciones.
- **Slither:** 1 finding Medium corregido; 5 Low (`timestamp`) aceptados con justificación. Sin High.

### 4.3 Riesgos residuales (honestos)
1. **Incentivo del que ya cobró.** Con garantía igual a un aporte, a quien cobra en el turno 1 de una ronda de N le conviene dejar de pagar si `N − 1 > 1`. Pierde la garantía, pero se ahorra los aportes restantes. El MVP **mitiga pero no elimina** el riesgo. El organizador puede pedir una garantía mayor (el contrato acepta cualquier valor ≥ aporte), y el roadmap propone garantías dinámicas.
2. **Ventaja del orden.** Inscribirse primero es cobrar primero, y eso incentiva el front-running de `join`. Se resuelve con VRF (roadmap).
3. **Liveness.** Si nadie llama a `closeRound`, la ronda no avanza. Cualquiera puede hacerlo, incluido el beneficiario, que es el más interesado. Chainlink Automation lo resuelve sin depender de nadie.
4. **Dependencia del token.** Un stablecoin real con lista negra (USDC) podría congelar la dirección de una ronda. Es un riesgo aceptado de usar stablecoins centralizadas.

## 5. Roadmap

| Fase | Entregable | Motivación |
|---|---|---|
| **Fase 1 (este MVP)** | Factory, ronda con garantía, tUSD, frontend, deploy verificado en Sepolia | Demostrar el flujo completo de punta a punta |
| **Fase 2: robustez** | Orden por **Chainlink VRF v2.5**; cierre automático con **Chainlink Automation**; garantía proporcional a los turnos restantes; exclusión del moroso | Cerrar los riesgos 1 a 3 |
| **Fase 3: producto** | USDC real en una L2 (Base o Arbitrum); rondas privadas con allowlist EIP-712; `permit` (EIP-2612); reputación on-chain (SBT); indexador con The Graph | Costo por transacción bajo, UX y confianza entre desconocidos |
| **Transversal** | Auditoría externa; verificación formal de la invariante de solvencia; clones EIP-1167 en la factory | Seguridad y costo de creación |

## 6. Conclusión

TrustRonda muestra que una práctica financiera comunitaria muy arraigada se puede llevar a la blockchain sin agregar un intermediario nuevo. El contrato toma el lugar del organizador: custodia los fondos, aplica las reglas y castiga el incumplimiento con una garantía que se ejecuta sola. El MVP prioriza un flujo principal completo, probado y verificable por sobre la cantidad de funciones. Los riesgos que quedan están identificados, y cada uno tiene su paso concreto en el roadmap.

---

*Direcciones de los contratos, URLs del código verificado y transacciones reales: ver las secciones 9 y 10 del README del repositorio.*
