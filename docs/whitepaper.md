# TrustRonda — Whitepaper técnico (Nivel 2)

**Ronda de ahorro rotativo on-chain con garantía ejecutable**

Carlos Binker · Ethereum Developer Pack, Nivel 2 (ETH Kipu / Talento Tech) · Octubre 2026
Versión 2.0: refleja el MVP **implementado y desplegado** en Sepolia. La versión 1.0, del Nivel 1, era el diseño conceptual.

---

## Resumen

TrustRonda lleva a Ethereum la ronda de ahorro rotativo (ROSCA): un grupo aporta un monto fijo en cada turno y en cada turno uno de los miembros se lleva el pozo. El contrato reemplaza al organizador como custodio, fija las reglas de forma inmutable, **sortea el orden de cobro con Chainlink VRF** (aleatoriedad verificable que nadie puede arreglar) y le pide a cada miembro una **garantía** que se ejecuta automáticamente si no paga, para que el beneficiario del turno cobre igual. El MVP consta de tres contratos (`TrustRondaFactory`, `TrustRonda` y `MockUSDC`) integrados con el coordinador de Chainlink VRF v2.5, tiene 70 tests con coverage del 100 % y análisis con Slither, y se opera desde un frontend en React.

---

## 1. Definición del problema

La ronda, también llamada *tanda*, *pasanaku*, *junta* o *susu*, es uno de los instrumentos de ahorro informal más extendidos del mundo. Sirve a personas con acceso limitado al crédito: el que cobra primero obtiene un préstamo sin interés, y el que cobra último ahorra con disciplina. Sus fallas son estructurales:

1. **Riesgo de custodia.** Un organizador junta el dinero. Puede desaparecer, equivocarse o favorecer a alguien.
2. **Riesgo de contraparte con incentivos desalineados.** Después de cobrar, a un miembro le conviene dejar de pagar: ya obtuvo su pozo y los turnos que quedan son solo costo. Los últimos del orden son los más expuestos.
3. **Reglas que se pueden discutir.** Orden de cobro, montos o qué pasa ante un atraso se acuerdan de palabra y se renegocian sobre la marcha. El orden importa mucho: cobrar primero equivale a un préstamo sin interés, y cobrar último, a ahorrar. Por eso se sortea, y el sorteo informal se puede arreglar.
4. **Sin registro verificable.** Ante un conflicto, es la palabra de uno contra la del otro.

Estas fallas limitan la ronda a círculos de confianza muy cercanos: familia, compañeros de trabajo.

## 2. Solución

TrustRonda ataca cada falla con una propiedad de la blockchain:

| Falla | Mecanismo en TrustRonda |
|---|---|
| Custodia | Los fondos los retiene el contrato. No existe ninguna función que permita a un tercero, ni al organizador ni al owner de la factory, mover fondos ajenos. |
| Incentivo a dejar de pagar | Garantía depositada al inscribirse. Si un miembro no paga antes del vencimiento, `closeRound` descuenta el aporte de su garantía y lo suma al pozo. |
| Reglas discutibles | Aporte, garantía, cupo y duraciones son `immutable`. |
| Sorteo arreglable | El orden de cobro se sortea con **Chainlink VRF v2.5**: un número aleatorio con prueba criptográfica que el contrato verifica on-chain. Ni el organizador, ni los miembros, ni el owner, ni el proposer del bloque pueden elegirlo o anticiparlo. |
| Sin registro | Cada acción emite un evento indexado, auditable en Etherscan y visible en el historial del frontend. |
| Dependencia de una persona | `closeRound` lo puede llamar cualquiera. Una ronda que no se llena se puede cancelar por cualquiera después del plazo, así la garantía nunca queda trabada. |

### 2.1 Por qué blockchain y no una app tradicional
Una app centralizada solucionaría el registro, pero no la custodia ni la inmutabilidad: el operador de la app pasaría a ser el nuevo organizador en el que hay que confiar. El valor de TrustRonda está justamente en que **no hay operador**: las reglas las ejecuta un código público y verificado, y los fondos solo salen hacia quien tiene derecho a ellos.

## 3. Arquitectura implementada

```
Usuario (MetaMask) ──► Frontend React + wagmi/viem
                          │
                          ├─► TrustRondaFactory ──new──► TrustRonda (una por ronda)
                          │    (Ownable)    ▲  │           (ReentrancyGuard, SafeERC20)
                          │                 │  │ fulfillDraw      │      ▲
                          │      requestDraw│  └──────────────────┘      │
                          │                 │                            │
                          │   requestRandomWords ▼ ▲ rawFulfillRandomWords
                          │            Chainlink VRF v2.5 Coordinator     │
                          │                                               │
                          └─► MockUSDC (tUSD) ◄────── safeTransfer ────────┘
```

### 3.1 Contratos

**`TrustRondaFactory`**: despliega cada ronda con `new` y la registra en un array con lectura paginada. Es el **único consumidor de Chainlink VRF**: cuando una ronda completa su cupo le pide el sorteo (`requestDraw`); la factory llama a `requestRandomWords` del coordinador y, cuando el oráculo responde (`rawFulfillRandomWords`), le entrega el número a la ronda (`fulfillDraw`). El coordinador es `immutable`. A propósito no se hereda `VRFConsumerBaseV2Plus`, cuyo `setCoordinator` le permitiría al owner apuntar a un coordinador propio y arreglar el sorteo. Mantiene además una **lista blanca de tokens** (`setTokenAllowed`, solo el owner) para evitar tokens fee-on-transfer o rebasing, que romperían la contabilidad. El owner no tiene ningún poder sobre las rondas ya creadas, sus fondos ni el sorteo.

**`TrustRonda`**: una ronda concreta. Máquina de estados `Open → Drawing → Active → Completed`, más `Open → Cancelled` y `Drawing → Cancelled` (si el sorteo no llega en `DRAW_TIMEOUT`).

| Función | Quién | Qué hace |
|---|---|---|
| `join()` | cualquiera, en `Open` | Deposita la garantía; el último del cupo pasa la ronda a `Drawing` y pide el sorteo |
| `fulfillDraw()` | solo la factory (que solo acepta al coordinador de VRF) | Sortea el orden (Fisher-Yates con el número de VRF) y arranca el turno 0 |
| `contribute()` | miembro, en `Active` | Paga el aporte del turno antes del vencimiento |
| `closeRound()` | cualquiera, en `Active` | Si pagaron todos o venció el plazo: ejecuta las garantías de los que no pagaron, acredita el pozo al beneficiario y avanza el turno |
| `withdraw()` | quien tenga saldo | Pull payment del pozo y, al terminar o cancelar, de la garantía |
| `cancel()` | en `Open`: organizador, o cualquiera tras `joinDeadline`; en `Drawing`: cualquiera tras `DRAW_TIMEOUT` | Cancela una ronda que no arrancó y libera las garantías |

**`MockUSDC`**: ERC20 de 6 decimales con faucet de 1.000 tUSD por día y cuenta. Existe solo para que la demo funcione en testnet.

### 3.2 Modelo de datos y gas
- Los siete parámetros de la ronda son `immutable`: se guardan en el bytecode y su lectura cuesta lo mismo que una constante.
- `status`, `currentRound`, `paidCount`, `roundDeadline` y `drawRequestedAt` comparten **un slot** (8 + 8 + 8 + 64 + 64 bits). Cada transición escribe un solo slot.
- El sorteo se hace en memoria (Fisher-Yates, un índice por paso derivado de `keccak256(randomWord, i)`) y escribe una sola vez por miembro. Con 12 miembros, el callback de VRF consume 372 k de gas con las reglas de Glamsterdam, activas en Sepolia desde el 06/10/2026, con un límite de 500 k (`CALLBACK_GAS_LIMIT`).
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
| Sorteo manipulable | Chainlink VRF en lugar de `block.timestamp` o `blockhash`; coordinador `immutable`; callback solo del coordinador; entrega a la ronda solo desde la factory. |
| Oráculo que no responde | `DRAW_TIMEOUT` = 1 día: después, cualquiera cancela y se devuelven las garantías. Un sorteo tardío se ignora sin revertir. |

### 4.2 Verificación
- **70 tests** (unitarios, de integración con el mock oficial de VRF, fuzz con 512 corridas, incluido que el sorteo siempre es una permutación, e invariantes con 128 × 64 llamadas). Coverage del 100 % en líneas, statements, branches y funciones.
- **Slither:** 2 findings Medium corregidos; 7 Low aceptados con justificación. Sin High.

### 4.3 Riesgos residuales (honestos)
1. **Incentivo del que ya cobró.** Con garantía igual a un aporte, a quien cobra en el turno 1 de una ronda de N le conviene dejar de pagar si `N − 1 > 1`. Pierde la garantía, pero se ahorra los aportes restantes. El MVP **mitiga pero no elimina** el riesgo. El organizador puede pedir una garantía mayor (el contrato acepta cualquier valor ≥ aporte), y el roadmap propone garantías dinámicas.
2. **Costo y dependencia del oráculo.** Cada sorteo consume saldo de la suscripción de VRF, que hoy financia el operador. Si la suscripción se queda sin fondos, el sorteo se demora; el timeout evita que las garantías queden trabadas, pero la ronda se cancela.
3. **Liveness.** Si nadie llama a `closeRound`, la ronda no avanza. Cualquiera puede hacerlo, incluido el beneficiario, que es el más interesado. Chainlink Automation lo resuelve sin depender de nadie.
4. **Dependencia del token.** Un stablecoin real con lista negra (USDC) podría congelar la dirección de una ronda. Es un riesgo aceptado de usar stablecoins centralizadas.

## 5. Viabilidad comercial

> Pedido explícito del profesor en la mentoría (clase 20, 0:14:06): el whitepaper tiene que incluir un análisis de viabilidad **comercial**, no solo técnico. Las cifras de esta sección son **supuestos de trabajo** para dimensionar el modelo, no datos de mercado verificados.

### 5.1 Mercado y usuarios
- **Práctica existente, no hay que crear el hábito.** La ronda es conocida en toda Latinoamérica (tanda en México, pasanaku en Bolivia, junta en Perú, "círculo" o "ronda" en Argentina), y también en África y Asia (susu, chit funds). El producto digitaliza algo que la gente ya hace; no le pide aprender un instrumento nuevo.
- **Usuario inicial:** grupos que **ya** hacen rondas y tienen el problema de confianza o de gestión. Compañeros de trabajo, comunidades migrantes que ahorran en dólares, emprendedores que juntan capital para mercadería y cooperativas pequeñas.
- **Por qué ahora:** las stablecoins ya se usan en la región para ahorrar en dólares, las L2 bajan el costo por transacción a centavos, y las wallets con login social reducen la barrera de entrada.

### 5.2 Propuesta de valor
| Para | Valor |
|---|---|
| Miembros | No tienen que confiar en un organizador; el sorteo es verificable; la garantía protege al que cobra último; el ahorro queda en dólares digitales. |
| Organizadores | No manejan efectivo ni planillas y no cargan con la responsabilidad de perseguir morosos: el contrato cobra, castiga y paga solo. |
| Comunidades y cooperativas | Una herramienta auditable para administrar fondos comunes, con historial público. |

### 5.3 Modelo de ingresos (propuesto)
1. **Comisión por ronda:** un porcentaje chico del pozo de cada turno (supuesto: 0,5 % a 1 %), cobrado por el contrato al acreditar el pozo. Financia la suscripción de VRF y la operación.
2. **Rondas premium para organizaciones:** cupos mayores, rondas privadas por invitación, reportes para cooperativas o fintechs que quieran ofrecer el producto con su marca (B2B2C).
3. **Rendimiento del colateral (fase 3, con cuidado regulatorio):** las garantías inmovilizadas podrían generar rendimiento en un protocolo de lending (por ejemplo, Aave) y repartirlo entre miembros y protocolo. Esto agrega riesgo de contraparte y se evalúa después de una auditoría.

### 5.4 Costos
| Concepto | Observación |
|---|---|
| Gas de los usuarios | En Ethereum mainnet es alto para aportes chicos. **Por eso el despliegue productivo apunta a una L2** (Base o Arbitrum), donde cada transacción cuesta centavos. |
| Chainlink VRF | Un sorteo por ronda (no por turno). Lo paga la suscripción y se recupera con la comisión. |
| Auditoría y desarrollo | Costo fijo inicial; indispensable antes de manejar fondos reales. |

### 5.5 Competencia y diferenciación
- **La ronda informal** (efectivo, WhatsApp, planilla) es la competencia principal. Es gratis y conocida, pero depende de la confianza y no tiene garantía ni sorteo verificable.
- **Apps fintech de ahorro grupal:** resuelven la gestión, pero el custodio sigue siendo una empresa.
- **Intentos previos on-chain de ROSCA:** validan la idea. TrustRonda se diferencia por combinar **garantía ejecutable + sorteo con VRF + pull payments**, y por apuntar a stablecoins en L2.

### 5.6 Riesgos de negocio
- **Regulatorio:** juntar ahorro de terceros puede estar regulado, según el país (en Argentina, por ejemplo, la captación de ahorro y los sistemas de ahorro previo). Antes de operar con fondos reales hace falta análisis legal. El diseño sin custodio intermedio ayuda, pero no lo resuelve solo.
- **Adopción:** wallets y stablecoins siguen siendo una barrera para parte del público objetivo → onboarding con login social y account abstraction (fase 3).
- **Riesgo de la stablecoin:** depeg o congelamiento de fondos por parte del emisor.
- **Incentivo del que ya cobró:** se mitiga con la garantía y, en el roadmap, con garantía dinámica y reputación.

### 5.7 Estrategia de salida al mercado
1. **Piloto** con grupos que ya hacen rondas (compañeros de trabajo, comunidades), en una L2 y con montos chicos.
2. **Socios:** cooperativas y fintechs que integren TrustRonda como "ronda con garantía" dentro de su app.
3. **Métricas de éxito:** rondas completadas sin cancelación, tasa de impago, retención (miembros que hacen una segunda ronda) y volumen ahorrado.

## 6. Roadmap

| Fase | Entregable | Motivación |
|---|---|---|
| **Fase 1 (este MVP)** | Factory, ronda con garantía, **sorteo con Chainlink VRF v2.5**, tUSD, frontend, deploy verificado en Sepolia | Demostrar el flujo completo de punta a punta |
| **Fase 2: robustez** | Cierre automático con **Chainlink Automation**; garantía proporcional a los turnos restantes; exclusión del moroso; comisión que financie la suscripción de VRF | Cerrar los riesgos 1 a 3 |
| **Fase 3: producto** | USDC real en una L2 (Base o Arbitrum); rondas privadas con allowlist EIP-712; `permit` (EIP-2612); reputación on-chain (SBT); indexador con The Graph | Costo por transacción bajo, UX y confianza entre desconocidos |
| **Transversal** | Auditoría externa; verificación formal de la invariante de solvencia; clones EIP-1167 en la factory | Seguridad y costo de creación |

## 7. Conclusión

TrustRonda muestra que una práctica financiera comunitaria muy arraigada se puede llevar a la blockchain sin agregar un intermediario nuevo. El contrato toma el lugar del organizador: custodia los fondos, sortea el orden con aleatoriedad verificable, aplica las reglas y castiga el incumplimiento con una garantía que se ejecuta sola. Comercialmente, digitaliza un hábito que ya existe, con un modelo de comisión simple y un camino claro hacia una L2. El MVP prioriza un flujo principal completo, probado y verificable por sobre la cantidad de funciones. Los riesgos que quedan están identificados, y cada uno tiene su paso concreto en el roadmap.

---

*Direcciones de los contratos, URLs del código verificado y transacciones reales: ver las secciones 9 y 10 del README del repositorio.*
