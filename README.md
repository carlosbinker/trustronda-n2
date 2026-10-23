# TrustRonda

**Ronda de ahorro rotativo on-chain, sin nadie que guarde la plata.**

Proyecto final del *Ethereum Developer Pack, Nivel 2: Smart Contract Developer* (ETH Kipu / Talento Tech, 2026).
Autor: Carlos Binker.

> Red: **Sepolia** · Contratos: **Solidity 0.8.24 + OpenZeppelin 5.1** · Framework: **Foundry** · Frontend: **React + Vite + wagmi/viem**
> Tests: **58 pasan** · Coverage: **100 %** en líneas, statements, branches y funciones · Slither: **sin findings High ni Medium**

---

## Índice

1. [Qué hace y por qué blockchain](#1-qué-hace-y-por-qué-blockchain)
2. [Arquitectura](#2-arquitectura)
3. [Estructura del repositorio](#3-estructura-del-repositorio)
4. [Instalación y compilación](#4-instalación-y-compilación)
5. [Tests y coverage](#5-tests-y-coverage)
6. [Slither](#6-slither)
7. [Deploy y verificación en Sepolia](#7-deploy-y-verificación-en-sepolia)
8. [Cómo usar el proyecto](#8-cómo-usar-el-proyecto)
9. [Red y direcciones desplegadas](#9-red-y-direcciones-desplegadas)
10. [Transacciones reales del flujo principal](#10-transacciones-reales-del-flujo-principal)
11. [Decisiones de diseño y seguridad](#11-decisiones-de-diseño-y-seguridad)
12. [Warnings analizados](#12-warnings-analizados)
13. [Limitaciones conocidas del MVP](#13-limitaciones-conocidas-del-mvp)
14. [Roadmap](#14-roadmap)
15. [Documentación adicional](#15-documentación-adicional)

---

## 1. Qué hace y por qué blockchain

### El problema
La **ronda** (también llamada *tanda*, *pasanaku*, *junta* o *ROSCA*) es una forma de ahorro muy usada en Latinoamérica: un grupo aporta el mismo monto todos los meses y en cada turno uno de los miembros se lleva el pozo. Funciona con dos supuestos frágiles:

- **Alguien guarda la plata.** El organizador junta los aportes y los entrega. Si desaparece, se pierde todo.
- **Todos pagan hasta el final.** El que ya cobró tiene incentivos para dejar de pagar, y los últimos son los que más arriesgan.

### La solución
TrustRonda reemplaza al organizador por un smart contract:

- Los aportes los custodia **el contrato**, no una persona. Nadie, ni el organizador ni el owner de la factory, puede mover fondos ajenos.
- Al inscribirse, cada miembro deja una **garantía**. Si no paga un turno a tiempo, el contrato ejecuta su garantía y **el beneficiario cobra igual**.
- El **orden de cobro** queda fijado on-chain (el orden de inscripción) y no se puede cambiar.
- Cada paso emite un **evento**: cualquiera puede auditar quién pagó, quién cobró y cuándo.

### Por qué tiene sentido en Web3
| Necesidad de la ronda | Qué aporta la blockchain |
|---|---|
| Custodia sin intermediario de confianza | El contrato retiene los fondos y solo los libera según reglas públicas |
| Reglas que nadie puede cambiar a mitad de camino | Parámetros `immutable`; sin owner sobre las rondas |
| Penalizar al que no paga sin juicios ni reclamos | Ejecución automática de la garantía en `closeRound` |
| Transparencia entre personas que no se conocen | Historial completo en eventos, verificable en Etherscan |
| Acceso con solo una wallet | Sin cuenta bancaria ni KYC; aportes en stablecoin |

---

## 2. Arquitectura

```mermaid
flowchart LR
    U[Usuario<br/>MetaMask] -->|React + wagmi/viem| F[Frontend<br/>/frontend]
    F -->|createRonda| FA[TrustRondaFactory]
    FA -- "new TrustRonda(...)<br/>(interacción entre contratos)" --> R1[TrustRonda #1]
    FA --> R2[TrustRonda #2]
    F -->|join · contribute · closeRound · withdraw| R1
    R1 -- "SafeERC20<br/>transferFrom / transfer" --> T[MockUSDC tUSD<br/>ERC20, 6 decimales]
    F -->|faucet · approve| T
```

| Contrato | Rol | Herencia (OpenZeppelin 5.1) |
|---|---|---|
| [`TrustRonda`](contracts/TrustRonda.sol) | **Contrato principal.** Una ronda: inscripción con garantía, aportes por turno, cierre de turno con ejecución de garantías y retiros (pull payment). | `ReentrancyGuard`, `SafeERC20` |
| [`TrustRondaFactory`](contracts/TrustRondaFactory.sol) | Crea rondas con `new`, lleva un registro paginado y una lista blanca de tokens. | `Ownable` |
| [`MockUSDC`](contracts/MockUSDC.sol) | Stablecoin de prueba (tUSD, 6 decimales) con faucet de 1.000 tUSD por día, para que cualquiera pruebe la demo. | `ERC20` |

### Ciclo de vida de una ronda

```mermaid
stateDiagram-v2
    [*] --> Open: factory.createRonda()
    Open --> Open: join() (garantía)
    Open --> Active: join() del último miembro
    Open --> Cancelled: cancel() (organizador, o cualquiera después de joinDeadline)
    Active --> Active: contribute() / closeRound() → turno siguiente
    Active --> Completed: closeRound() del último turno
    Completed --> [*]: withdraw() (pozos + garantía)
    Cancelled --> [*]: withdraw() (garantía)
```

### Flujo principal (ejemplo con 3 miembros, aporte 100, garantía 100)

1. **Crear:** el organizador llama a `factory.createRonda(tUSD, 100, 100, 3, 1 día, 7 días)`.
2. **Inscribirse:** Alice, Bob y Carol hacen `approve` y `join()`; cada uno deja 100 de garantía. Con Carol se completa el cupo y arranca el turno 1.
3. **Turno 1:** los tres llaman a `contribute()` (100 cada uno). Cualquiera llama a `closeRound()`: se acreditan 300 a Alice.
4. **Turno 2:** idem, cobra Bob. Si Carol no paga, al vencer el turno se ejecutan 100 de su garantía y Bob cobra los 300 igual.
5. **Turno 3:** cobra Carol. La ronda pasa a `Completed`.
6. **Retirar:** cada uno llama a `withdraw()` y se lleva su pozo y lo que le quede de garantía.

### Roles y privilegios

| Rol | Puede | No puede |
|---|---|---|
| Organizador de una ronda | Cancelarla mientras está en `Open` | Mover fondos, cambiar parámetros ni el orden |
| Miembro | `join`, `contribute`, `withdraw` de lo propio | Cobrar fuera de su turno |
| Cualquier cuenta | `closeRound` cuando corresponde; `cancel` después de `joinDeadline` | Nada sobre fondos ajenos |
| Owner de la factory | `setTokenAllowed` (lista blanca de tokens para rondas **futuras**) | Tocar rondas existentes o sus fondos |

---

## 3. Estructura del repositorio

```
trustronda-n2/
├── contracts/              # Solidity con NatSpec completo
│   ├── TrustRonda.sol
│   ├── TrustRondaFactory.sol
│   └── MockUSDC.sol
├── test/                   # Foundry: unit, integración, fuzz e invariant
│   ├── TrustRonda.t.sol
│   ├── TrustRondaFactory.t.sol
│   ├── MockUSDC.t.sol
│   ├── TrustRonda.fuzz.t.sol
│   ├── invariant/          # Handler + invariantes de solvencia
│   └── utils/BaseTest.sol
├── script/
│   ├── Deploy.s.sol        # deploy + verificación
│   ├── Demo.s.sol          # flujo completo on-chain con 2 wallets
│   └── verify-ronda.sh     # verifica rondas creadas por la factory
├── deployments/            # direcciones por chainId (las genera Deploy)
├── frontend/               # dApp React + Vite + wagmi/viem
├── docs/                   # whitepaper, Slither, explicación, guion del video
├── foundry.toml · Makefile · .env.example
└── lib/                    # submódulos: openzeppelin-contracts v5.1.0, forge-std v1.9.6
```

---

## 4. Instalación y compilación

**Requisitos:** [Foundry](https://book.getfoundry.sh/getting-started/installation), Node.js 20 o superior, Git y, para Slither, Python 3 con `pip`.

```bash
git clone --recurse-submodules https://github.com/<TU_USUARIO>/trustronda-n2.git
cd trustronda-n2

# si se clonó sin --recurse-submodules:
git submodule update --init --recursive

forge build                 # o: make build
```

El proyecto compila **sin warnings** de solc ni de `forge lint` (ver [Warnings analizados](#12-warnings-analizados)).

---

## 5. Tests y coverage

```bash
forge test -vv                                     # o: make test
forge coverage --no-match-coverage "(script|test)" # o: make coverage
forge test --gas-report                            # consumo de gas por función
```

**Resultado:** 58 tests, 0 fallas ([`docs/reports/forge-test.txt`](docs/reports/forge-test.txt)).

| Suite | Tests | Qué cubre |
|---|---|---|
| `TrustRonda.t.sol` | 37 | Flujo completo de punta a punta, cada función en su camino exitoso y en cada revert (custom errors con parámetros), eventos (`vm.expectEmit`), ejecución de garantías y las 11 validaciones del constructor |
| `TrustRondaFactory.t.sol` | 10 | Creación y registro (interacción entre contratos), lista blanca, permisos del owner, paginación |
| `MockUSDC.t.sol` | 4 | Faucet y cooldown |
| `TrustRonda.fuzz.t.sol` | 3 × 512 corridas | **Conservación del dinero** con parámetros y patrones de pago aleatorios (`bound`); todos terminan con su saldo si todos pagan; no se puede cerrar antes de tiempo |
| `invariant/` | 4 × 128 × 64 llamadas | **Solvencia exacta:** saldo del token = pozos acreditados + garantías + aportes del turno abierto; cupo, turnos y garantías dentro de sus límites |

**Coverage del código propio** ([`docs/reports/coverage.txt`](docs/reports/coverage.txt)):

| Archivo | Líneas | Statements | Branches | Funciones |
|---|---|---|---|---|
| `MockUSDC.sol` | 100 % (9/9) | 100 % (10/10) | 100 % (1/1) | 100 % (2/2) |
| `TrustRonda.sol` | 100 % (116/116) | 100 % (137/137) | 100 % (23/23) | 100 % (18/18) |
| `TrustRondaFactory.sol` | 100 % (25/25) | 100 % (27/27) | 100 % (4/4) | 100 % (5/5) |
| **Total** | **100 %** | **100 %** | **100 %** | **100 %** |

Se excluyen `test/` y `script/` (código auxiliar) y `lib/` (librerías de terceros), como permite el enunciado.

---

## 6. Slither

```bash
pip install slither-analyzer
slither . --filter-paths "lib|test|script" --exclude-dependencies   # o: make slither
```

| Detector | Severidad | Estado |
|---|---|---|
| `uninitialized-local` (`closeRound`) | Medium | **Corregido** |
| `timestamp` (×5: `join`, `contribute`, `closeRound`, `cancel`, `faucet`) | Low | **Aceptado**, con justificación técnica |

Justificación de los `timestamp`, en resumen: se usa `block.timestamp` para **plazos de calendario** (mínimo 5 minutos, típicamente días), no para aleatoriedad. El margen de manipulación de un proposer es de segundos, ningún monto se calcula con el tiempo, y el peor caso es darle unos segundos más a alguien para pagar. Informe completo con la revisión manual: [`docs/slither.md`](docs/slither.md).

---

## 7. Deploy y verificación en Sepolia

1. Copiar las variables de entorno y completarlas. **`.env` está en `.gitignore`: nunca se commitea.**
   ```bash
   cp .env.example .env
   # SEPOLIA_RPC_URL, PRIVATE_KEY (wallet SOLO de testnet), ETHERSCAN_API_KEY
   # PRIVATE_KEY_2 (segunda wallet de testnet, solo para la demo por script)
   ```
2. Desplegar y verificar MockUSDC y TrustRondaFactory:
   ```bash
   make deploy
   # = forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --verify -vvv
   ```
   Las direcciones quedan en `deployments/11155111.json` y las transacciones en `broadcast/Deploy.s.sol/11155111/`.
3. Ejecutar el flujo principal on-chain (crea una ronda de 2 miembros y la juega completa):
   ```bash
   make demo
   ```
4. Verificar las rondas creadas por la factory. Se despliegan con `new`, así que `--verify` no las cubre:
   ```bash
   make verify-ronda RONDA=0x...
   ```

---

## 8. Cómo usar el proyecto

### Frontend local
```bash
cd frontend
cp .env.example .env.local      # completar con deployments/11155111.json
npm install
npm run dev                     # http://localhost:5173
```

| Variable | Valor |
|---|---|
| `VITE_CHAIN_ID` | `11155111` (Sepolia) |
| `VITE_FACTORY_ADDRESS` | dirección de `TrustRondaFactory` |
| `VITE_USDC_ADDRESS` | dirección de `MockUSDC` |
| `VITE_DEPLOY_BLOCK` | `deployBlock` del JSON (desde ahí se leen los eventos) |
| `VITE_RPC_URL` | opcional: RPC propio para lecturas |

Frontend desplegado: **PENDIENTE: completar con la URL de Vercel** (opcional según el checklist).

### Paso a paso en la dApp
1. **Conectar wallet** (MetaMask en Sepolia; si está en otra red, aparece el botón para cambiar).
2. **Pedir 1.000 tUSD de prueba** con el faucet.
3. **Crear una ronda:** aporte, garantía, cupo y duración. Para la demo, 2 miembros y turnos de 5 minutos.
4. Con cada cuenta: **Inscribirme**. La dApp manda `approve` y después `join`.
5. En cada turno: **Pagar** (`approve` + `contribute`) con cada miembro, y después **Cerrar turno** (lo puede hacer cualquiera).
6. **Retirar** el pozo cobrado y, al terminar, la garantía.

La **rueda** muestra los lugares en orden de cobro: los que ya cobraron, el turno en curso, quién pagó y quién tuvo impagos. El **historial on-chain** lista los eventos del contrato con el link de cada transacción en Etherscan.

---

## 9. Red y direcciones desplegadas

**Red:** Ethereum Sepolia (chainId `11155111`)

| Contrato | Dirección | Código verificado |
|---|---|---|
| MockUSDC (tUSD) | **PENDIENTE: completar tras `make deploy`** | `https://sepolia.etherscan.io/address/<DIRECCION>#code` |
| TrustRondaFactory | **PENDIENTE** | `https://sepolia.etherscan.io/address/<DIRECCION>#code` |
| TrustRonda (ronda de la demo) | **PENDIENTE: la imprime `make demo`** | `https://sepolia.etherscan.io/address/<DIRECCION>#code` |

---

## 10. Transacciones reales del flujo principal

Las genera `make demo` (están en `broadcast/Demo.s.sol/11155111/run-latest.json`) o el frontend (se ven en el historial de cada ronda).

| Paso | Función | Tx |
|---|---|---|
| Crear ronda | `TrustRondaFactory.createRonda` | **PENDIENTE** |
| Inscripción miembro 1 | `TrustRonda.join` | **PENDIENTE** |
| Inscripción miembro 2 (arranca la ronda) | `TrustRonda.join` | **PENDIENTE** |
| Aporte turno 1 | `TrustRonda.contribute` | **PENDIENTE** |
| Cierre turno 1 | `TrustRonda.closeRound` | **PENDIENTE** |
| Retiro del pozo | `TrustRonda.withdraw` | **PENDIENTE** |
| Cierre turno 2 (Completed) | `TrustRonda.closeRound` | **PENDIENTE** |
| Retiro final | `TrustRonda.withdraw` | **PENDIENTE** |

---

## 11. Decisiones de diseño y seguridad

| Ítem del checklist (B) | Cómo se cumple |
|---|---|
| NatSpec completo | Contratos, variables de estado, structs, eventos y sus parámetros, custom errors y sus parámetros, modifiers, funciones con `@param` y `@return`. Los roles están en el `@dev` de cada contrato. |
| Custom errors | 14 en `TrustRonda`, 2 en la factory y 1 en el token, con parámetros (`InvalidStatus(expected, actual)`, `RoundStillOpen(deadline)`…). Ningún `require` con string. |
| Strings y bytes largos | No hay. |
| Lecturas repetidas de storage | Se cachean en locales (`round`, `paid`, `deadline`, `amount` en `closeRound`). |
| storage / memory / calldata | `MemberInfo storage info` para modificar en el lugar; `memory` solo en los retornos de las views. |
| `constant` / `immutable` | Límites como `constant` (`MAX_MEMBERS`, `MIN_DURATION`…); los 7 parámetros de la ronda como `immutable`. |
| Empaquetado de storage | `status`, `currentRound`, `paidCount` y `roundDeadline` en **un slot**; `MemberInfo` (uint128 + uint8 + uint8 + bool) en **un slot**. |
| Visibilidad y mutabilidad | `external` para la API, `internal view` para helpers, `pure` en `decimals()`, estado `private` con getters. |
| Eventos | 9 eventos en `TrustRonda` con `indexed` en direcciones y turnos; el frontend arma el historial con ellos. |
| CEI | `join`, `contribute` y `withdraw` siguen *checks → effects → interactions*; `closeRound` no hace llamadas externas. |
| Reentrancy | `nonReentrant` en las tres funciones que transfieren, además de CEI. |
| Control de acceso | `Ownable` (OZ v5, `initialOwner` explícito) solo en la factory, con un único privilegio; sin owner en las rondas. |
| SafeERC20 | Todas las transferencias de la ronda usan `safeTransfer` / `safeTransferFrom`. |
| Pull payments | Pozos y garantías se acreditan y cada uno los retira: ningún receptor puede bloquear a otro. |
| DoS por loops | Único loop acotado por `MAX_MEMBERS = 12` (gas máximo medido de `closeRound`: ~200 k); `getRondas` paginado. |
| `unchecked` | Solo en contadores acotados por 12 y en restas ya validadas, cada uno con comentario. |
| `tx.origin`, `delegatecall`, `selfdestruct`, assembly | No se usan. |
| Proxies | No se usan: la ronda es inmutable a propósito (nadie puede cambiar las reglas a mitad de la ronda). |

**Gas** (`forge test --gas-report`, mediana): `join` 117 k · `contribute` 73 k · `closeRound` 72 k (máx. 200 k con 12 impagos) · `createRonda` 1,23 M (despliega una ronda).

---

## 12. Warnings analizados

| Origen | Warning | Decisión |
|---|---|---|
| `forge lint` | `unsafe-typecast` en los casts a `uint8` y `uint128` de `join` y `closeRound` | Seguros: los valores están acotados por `MAX_MEMBERS` y por la validación del constructor. Se justifican con `forge-lint: disable-next-line` y un comentario. |
| `forge lint` | `screaming-snake-case-immutable` | Excluido en `foundry.toml`: los `immutable` (`token`, `contributionAmount`…) son la API pública que lee el frontend y se leen como parámetros, no como constantes. |
| `forge lint` | `unsafe-cheatcode` (`vm.readFile` en `Demo.s.sol`) | Intencional, limitado por `fs_permissions` a `./deployments`. |
| `forge lint` | `unwrapped-modifier-logic` | **Corregido:** la lógica de los modifiers se movió a `_checkStatus` y `_checkMember`. |
| Vite | Chunk > 500 kB | viem + wagmi pesan unos 180 kB gzip. Es aceptable para una dApp de una página, así que se subió el umbral. |

---

## 13. Limitaciones conocidas del MVP

- **Orden de cobro por inscripción.** Es simple y transparente, pero el que se inscribe primero cobra primero, y en una ronda con desconocidos eso es una ventaja (y un incentivo a hacer front-running de la inscripción). → Roadmap: sorteo con Chainlink VRF.
- **La garantía cubre un número limitado de impagos.** Con garantía igual a un aporte, alcanza para un impago. Después, el pozo de los turnos siguientes sale más chico. → Roadmap: garantía proporcional a los turnos restantes y exclusión del moroso.
- **Un miembro que ya cobró y deja de pagar** solo pierde su garantía. El contrato no puede perseguirlo fuera de la cadena. → Roadmap: garantía decreciente y reputación on-chain.
- **El cierre del turno depende de que alguien llame a `closeRound`.** Puede hacerlo cualquiera, pero no se dispara solo. → Roadmap: Chainlink Automation.
- **Un solo token (tUSD de prueba)** en la lista blanca. La factory permite agregar USDC real con `setTokenAllowed`.
- **Máximo 12 miembros** por ronda, para acotar el gas del loop.
- **El frontend lee los eventos con `getLogs`.** Con muchas rondas o un RPC público restrictivo puede ser lento. → Roadmap: indexador (The Graph).

---

## 14. Roadmap

**Fase 2: robustez del protocolo**
- Sorteo del orden de cobro con **Chainlink VRF v2.5**, al completar el cupo.
- Cierre automático de turnos con **Chainlink Automation** (`checkUpkeep` / `performUpkeep` sobre `closeRound`).
- Garantía dinámica: proporcional a lo que falta pagar, y que decrezca para quien ya pagó más de lo que cobró.
- Exclusión del miembro con dos impagos (deja de recibir el pozo, que se reparte).

**Fase 3: producto**
- Soporte de **USDC real** en una L2 (Base o Arbitrum) para bajar el costo por transacción.
- Rondas privadas por invitación (allowlist con firma EIP-712) y `permit` (EIP-2612) para ahorrar el `approve`.
- Reputación on-chain: historial de rondas cumplidas como credencial (SBT).
- Indexador con The Graph y notificaciones de vencimiento.

**Seguridad y escalabilidad**
- Auditoría externa y testing formal de las invariantes (Halmos o Certora).
- Clones mínimos (EIP-1167) en la factory para bajar el costo de crear una ronda (hoy ~1,2 M de gas, porque se despliega el bytecode completo).
- Si se agregan funciones administrativas, pasar a `AccessControl` con multisig y timelock.

---

## 15. Documentación adicional

- [`docs/whitepaper.md`](docs/whitepaper.md): problema, solución, arquitectura implementada, seguridad, riesgos y roadmap.
- [`docs/explicacion-del-proyecto.md`](docs/explicacion-del-proyecto.md): explicación detallada de cada parte del código.
- [`docs/slither.md`](docs/slither.md): informe de análisis estático.
- [`docs/guion-video.md`](docs/guion-video.md): guion del video de 5 minutos.
- [`docs/guia-entrega.md`](docs/guia-entrega.md): pasos para desplegar, verificar, publicar en GitHub y entregar.
- [`docs/practica-remix.md`](docs/practica-remix.md): práctica guiada para jugar una ronda a mano en Remix VM.

## Licencia

MIT
