# Práctica guiada: jugar una ronda de TrustRonda en Remix

**Objetivo:** entender cada función tocándola con los botones de Remix, sin terminal. Es el mismo flujo que prueba `test_FullCycle_AllPay_EveryoneEndsEven`, pero hecho a mano.

**Tiempo:** unos 30 minutos para el flujo completo, más 10 si hacés los experimentos del final.
**Red:** Remix VM (blockchain simulada en el navegador). No gastás nada y no necesitás MetaMask.

> Recordatorio de unidades: tUSD tiene **6 decimales**. `1 tUSD = 1000000`. En los campos de Remix siempre se escriben los números enteros "crudos":
>
> | Querés decir | Escribís |
> |---|---|
> | 50 tUSD | `50000000` |
> | 100 tUSD | `100000000` |
> | 1.000 tUSD | `1000000000` |
> | 5 minutos | `300` |
> | 1 día | `86400` |

---

## Paso 1: Cargar los contratos

1. Abrir **https://remix.ethereum.org**.
2. En *File Explorer*, crear una carpeta `trustronda` y adentro tres archivos con **exactamente** estos nombres, pegando el contenido de cada uno desde `contracts/` del repo:
   - `MockUSDC.sol`
   - `TrustRonda.sol`
   - `TrustRondaFactory.sol`

   Tienen que estar en la misma carpeta, porque la factory importa `./TrustRonda.sol`.
3. Los imports `@openzeppelin/contracts/...` **no hay que tocarlos**: Remix los baja solo desde npm.
   Si te llegara a dar errores de compilación dentro de OpenZeppelin, cambiá `@openzeppelin/contracts/` por `@openzeppelin/contracts@5.1.0/` en los imports de los tres archivos. Así Remix usa la misma versión que el repo.

## Paso 2: Compilar

1. Ir a la pestaña **Solidity Compiler** (segundo ícono).
2. Compiler: **0.8.24**.
3. Abrir *Advanced Configurations*:
   - **EVM Version: cancun** (la misma que en `foundry.toml`)
   - **Enable optimization: sí, 200 runs**
4. Abrir `TrustRondaFactory.sol` y tocar **Compile**. Compila los tres archivos, porque la factory importa la ronda.
   Con `MockUSDC.sol` abierto, compilá también ese.

Tiene que aparecer el tilde verde, sin errores.

## Paso 3: Preparar las cuentas

En la pestaña **Deploy & Run Transactions**:
- Environment: **Remix VM (Cancun)**.
- En *Account* hay varias cuentas con 100 ETH de mentira. Vamos a usar dos:
  - **Cuenta A** = la primera (`0x5B3…eddC4`). Es la organizadora y el miembro 1.
  - **Cuenta B** = la segunda (`0xAb8…35cb2`). Es el miembro 2.

Tip: copiá las dos direcciones (con el ícono de copiar al lado del selector) en un bloc de notas, porque las vas a pegar varias veces.

## Paso 4: Desplegar el oráculo simulado, el token y la factory (con la cuenta A)

**4.0. Chainlink VRF simulado (mock oficial)**
En Remix VM no existe Chainlink, así que usamos el mock que trae Chainlink para tests y hacemos de oráculo a mano.
1. Crear `VRFMock.sol` con una sola línea de import (Remix lo baja de npm):
   ```solidity
   // SPDX-License-Identifier: MIT
   pragma solidity ^0.8.24;
   import "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
   ```
   Compilarlo y, en *Contract*, elegir **`VRFCoordinatorV2_5Mock`**. Si Remix no resuelve `@chainlink/contracts`, probá con `@chainlink/contracts@1.3.0/src/...`.
2. **Deploy** con `_baseFee = 100000000000000000`, `_gasPrice = 1000000000`, `_weiPerUnitLink = 4000000000000000`. **Copiá la dirección** (es `VRF`).
3. `createSubscription` → transact. Para obtener el id: botón azul `getActiveSubscriptionIds(0, 10)` → copiá el número largo (es `SUB_ID`).
4. `fundSubscription(SUB_ID, 1000000000000000000000)` → la suscripción queda con fondos de mentira.

**4.1. MockUSDC**
- Contract: `MockUSDC`. Botón **Deploy** (no lleva argumentos).
- En *Deployed Contracts* aparece `MOCKUSDC AT 0x…`. **Copiá esa dirección** (es `USDC`).

**4.2. TrustRondaFactory**
- Contract: `TrustRondaFactory`. Al lado de Deploy, desplegá los campos:
  - `initialOwner`: dirección de la **cuenta A**
  - `initialToken`: dirección de **USDC**
  - `vrfCoordinator_`: dirección de **VRF**
  - `keyHash_`: `0x0000000000000000000000000000000000000000000000000000000000000001` (en el mock da igual)
  - `subscriptionId_`: **SUB_ID**
  - `nativePayment_`: `false`
- **Deploy** → aparece `TRUSTRONDAFACTORY AT 0x…` (es `FACTORY`).
- En el **mock de VRF**: `addConsumer(SUB_ID, FACTORY)`. Sin esto, la factory no puede pedir sorteos.

**Qué estás viendo:** con Ownable de OpenZeppelin v5 el owner se pasa explícito. La factory ya habilita tUSD en el constructor, y lo podés comprobar con el botón azul `isTokenAllowed(USDC)` → `true`.

## Paso 5: Darle tUSD a las dos cuentas

En el contrato **MOCKUSDC** desplegado:
1. Cuenta **A** seleccionada → botón naranja **faucet**.
2. Cambiar a cuenta **B** → **faucet**.
3. Comprobar: `balanceOf(cuenta A)` → `1000000000` (1.000 tUSD). Lo mismo para B.

**Para probar el custom error:** con B, tocá **faucet** otra vez. La transacción revierte, y en la consola de abajo Remix muestra `FaucetCooldown` con el timestamp a partir del cual se puede volver a pedir.

## Paso 6: Crear la ronda (con la cuenta A)

En **TRUSTRONDAFACTORY**, desplegá `createRonda` y completá:

| Campo | Valor | Significa |
|---|---|---|
| `token` | dirección de USDC | se aporta en tUSD |
| `contributionAmount` | `50000000` | 50 tUSD por turno |
| `collateralAmount` | `50000000` | 50 tUSD de garantía |
| `maxMembers` | `2` | 2 miembros → 2 turnos |
| `roundDuration` | `300` | turnos de 5 minutos |
| `joinWindow` | `86400` | 1 día para completar el cupo |

**transact** con la cuenta A.

**Cómo obtener la dirección de la ronda:** botón azul `getRondas` con `offset = 0` y `limit = 1` → devuelve `[0x…]`. **Copiá esa dirección** (es `RONDA`).

**Cargar la ronda en Remix:**
1. En el selector *Contract*, elegí **`TrustRonda`** (no la factory).
2. Pegá `RONDA` en el campo **At Address** y tocá ese botón (no Deploy).
3. Aparece `TRUSTRONDA AT 0x…` con todos sus botones.

**Qué estás viendo:** la ronda no la desplegaste vos, la desplegó la factory con `new`. Esa es la **interacción entre contratos** del checklist. Probá los botones azules:
- `status` → `0` (Open)
- `organizer` → cuenta A (no la factory: la factory le pasa `msg.sender`)
- `factory` → FACTORY
- `contributionAmount` → `50000000`, `maxMembers` → `2`, `joinDeadline` → un timestamp

## Paso 7: Inscribirse (approve + join)

Un contrato no puede sacarte tokens sin permiso. Por eso siempre van **dos pasos**: primero `approve` en el token, después la acción en la ronda.

**Cuenta A:**
1. En **MOCKUSDC** → `approve(spender = RONDA, value = 50000000)` → transact.
2. En **TRUSTRONDA** → **join**.
3. Comprobar: `memberCount` → `1`; `getMemberInfo(cuenta A)` → `collateral: 50000000, position: 0, defaults: 0, isMember: true`.

**Cuenta B:** lo mismo (`approve` 50000000 → `join`).

**Comprobar que se pidió el sorteo:**
- `status` → `1` (**Drawing**). El último en inscribirse completó el cupo y la ronda le pidió el sorteo a la factory, que se lo pidió a Chainlink VRF.
- En la factory: `drawRequestOf(RONDA)` → un número (es `REQUEST_ID`, en el mock suele ser `1`).
- En la consola, el detalle de la tx de `join` de B muestra los eventos `MemberJoined`, `RondaFull`, el `RandomWordsRequested` del coordinador y el `DrawRequested` de la factory: **cuatro contratos en una sola transacción**.

**Experimento:** con A, tocá `contribute` ahora → revierte con `InvalidStatus(2, 1)`: esperaba Active (2) y la ronda está Drawing (1).

## Paso 7b: Hacer de oráculo (el sorteo)

En la vida real, unos bloques después el oráculo de Chainlink responde solo. Acá lo hacés vos:
1. En el **mock de VRF**: `fulfillRandomWords(REQUEST_ID, FACTORY)` → transact (con cualquier cuenta).
2. Comprobar en la ronda:
   - `status` → `2` (Active); `roundDeadline` → ahora + 300.
   - `getMembers` → el **orden sorteado**. Puede haber quedado A, B o B, A. Llamá **P1** al primero y **P2** al segundo.
   - `currentBeneficiary` → P1.
   - En los logs: `DrawFulfilled` (factory), `PayoutOrderDrawn` con el número aleatorio y el orden, `RondaStarted` y `NewRound`.
3. **Experimento:** con cualquier cuenta, en la factory, `rawFulfillRandomWords(REQUEST_ID, [123])` → revierte con `OnlyCoordinatorCanFulfill`. **Nadie puede "elegir" el número:** solo el coordinador puede entregarlo.

## Paso 8: Turno 0 (cobra P1)

1. **Cuenta A:** MOCKUSDC `approve(RONDA, 50000000)` → TRUSTRONDA **contribute**.
2. **Cuenta B:** lo mismo.
3. Comprobar: `paidCount` → `2`; `hasPaid(0, cuenta A)` → `true`.
4. **Cualquier cuenta:** **closeRound**. Lo puede llamar cualquiera.
5. Comprobar:
   - `withdrawable(P1)` → `payout: 100000000, collateral: 0`. Tiene 100 tUSD acreditados (pull payment) y la garantía todavía no se libera.
   - `currentRound` → `1`, `currentBeneficiary` → P2.
6. **P1:** **withdraw** → su `balanceOf` sube 100 tUSD.
7. **Experimento:** P1 toca **withdraw** de nuevo → revierte con `NothingToWithdraw`. Es CEI: el saldo se puso en cero antes de transferir.

**Qué estás viendo:** `closeRound` **no transfiere**, solo acredita. El dinero sale recién cuando cada uno llama a `withdraw`. Ese es el patrón *pull payment*.

## Paso 9: Turno 1 (cobra P2)

1. A y B: `approve(RONDA, 50000000)` + **contribute**.
2. **closeRound**.
3. Comprobar: `status` → `3` (Completed); `currentRound` → `2`.
4. `withdrawable(P1)` → `payout: 0, collateral: 50000000`: recupera su garantía.
   `withdrawable(P2)` → `payout: 100000000, collateral: 50000000`.
5. A y B: **withdraw**.

## Paso 10: Verificar que nadie ganó ni perdió

- `balanceOf(cuenta A)` → `1000000000`
- `balanceOf(cuenta B)` → `1000000000`
- `balanceOf(RONDA)` → `0`

**Las cuentas cierran.** Es la propiedad que prueba el fuzz test `testFuzz_AllPay_EveryoneEndsEven` con cupos de 2 a 12 miembros y aportes aleatorios.

---

## Experimentos extra (los casos interesantes)

### A. Qué pasa si alguien no paga (ejecución de garantía)
1. Crear otra ronda igual (Paso 6) y cargarla con *At Address* (`getRondas(1, 1)` te da la segunda).
2. A y B se inscriben (Paso 7) y hacés de oráculo con el nuevo `drawRequestOf` (Paso 7b).
3. Turno 0: **solo P1** (el que cobra este turno) paga; P2 no.
4. Tocar **closeRound** enseguida → revierte con `RoundStillOpen(deadline)`. Falta un pago y el turno no venció.
5. **Esperar 5 minutos reales.** En Remix VM no se puede adelantar el reloj como con `vm.warp`, pero el turno dura 300 segundos.
6. **closeRound** otra vez → ahora sí. En los logs aparece `CollateralSlashed(P2, 0, 50000000)`.
7. `withdrawable(P1)` → `payout: 100000000`. **P1 cobró el pozo completo aunque P2 no pagó.**
8. `getMemberInfo(P2)` → `collateral: 0, defaults: 1`.

Es el corazón de la propuesta de valor, y lo prueba `test_CloseRound_Default_SlashesCollateral`.

### B. Cancelar una ronda que no se llena
1. Crear una ronda con `maxMembers = 3`. Solo A se inscribe.
2. Con **B**, tocar **cancel** → revierte con `NotAuthorizedToCancel`: solo el organizador puede, mientras la inscripción esté vigente.
3. Con **A** (organizadora): **cancel** → `status` = `4` (Cancelled).
4. A: **withdraw** → recupera su garantía.

### C. Permisos del owner de la factory
- Con **B**, en la factory: `setTokenAllowed(USDC, false)` → revierte con `OwnableUnauthorizedAccount(B)`.
- Con **A**: funciona. Pero las rondas ya creadas siguen funcionando igual: el owner no tiene poder sobre ellas.

### D. Ver el gas y el debugger
- En la consola, cada transacción muestra *gas* y *transaction cost*. Compará `join` (~129 k) con `contribute` (~73 k): `join` escribe más storage (array, struct y estado). El último `join` cuesta más (~286 k) porque además pide el sorteo a VRF.
- Botón **Debug** de cualquier tx: recorre opcode por opcode y muestra cómo cambian el storage y las variables. Sirve para ver el orden **checks → effects → interactions**: la llamada a `transferFrom` aparece al final.

---

## Cómo se relaciona esto con el proyecto

| Lo que hiciste a mano en Remix | Dónde está automatizado en el repo |
|---|---|
| Pasos 4 a 10 completos | `test/TrustRonda.t.sol` → `test_FullCycle_AllPay_EveryoneEndsEven` |
| Hacer de oráculo con el mock de VRF (Paso 7b) | `_fulfill` / `_fulfillWith` en `test/utils/BaseTest.sol`; en Sepolia lo hace Chainlink solo |
| Cada revert que provocaste | Los 34 tests `test_RevertWhen_*` |
| Esperar 5 minutos para el impago | `vm.warp(deadline + 1)` en los tests (instantáneo) |
| Probar con 2 miembros y 50 tUSD | El fuzzing prueba 512 combinaciones de 2 a 12 miembros y montos al azar |
| Desplegar con botones | `script/Deploy.s.sol` (`make deploy`) |
| Jugar la ronda con dos cuentas | `script/Demo.s.sol` (`make demo`) y el frontend |

Remix te deja **ver y entender** cada paso. Foundry lo **automatiza, lo repite y lo demuestra**, que es lo que evalúa el checklist.
