# Guía de entrega, paso a paso (WSL2)

Todo lo que queda para cerrar la entrega del **martes 27/10 a las 23:59**. Los pasos están en orden y cada uno indica qué ítem del checklist cierra.

## 1. Preparar el entorno (una sola vez)
```bash
# Foundry
curl -L https://foundry.paradigm.xyz | bash && foundryup
# Slither
pip install slither-analyzer
# Node 20 o superior (si no está): https://nodejs.org o nvm
```

## 2. Conseguir lo necesario para Sepolia
| Qué | Dónde |
|---|---|
| **Wallet A** (deployer y miembro 1) y **wallet B** (miembro 2) | MetaMask → crear dos cuentas **solo para testnet** |
| Sepolia ETH para las dos | Faucet de Google Cloud Web3, Alchemy o Infura (unos 0,05 ETH cada una alcanza) |
| RPC de Sepolia | Alchemy o Infura → crear app → URL de Sepolia |
| API key de Etherscan | etherscan.io → My Account → API Keys (sirve para Sepolia) |
| LINK de testnet (para pagar el sorteo de VRF) | [faucets.chain.link/sepolia](https://faucets.chain.link/sepolia) con la wallet A |
| **Suscripción de Chainlink VRF** | [vrf.chain.link](https://vrf.chain.link) → conectar la **wallet A** → red Sepolia → *Create Subscription* → *Add funds* (por ejemplo, 10 LINK) → copiar el **Subscription ID**. **No agregues el consumer a mano: lo hace `make deploy`.** |

Para exportar una private key en MetaMask: cuenta → ⋮ → Detalles de la cuenta → Mostrar clave privada. **Nunca la pegues en un archivo que se commitee** y nunca uses una wallet con fondos reales.

## 3. Clonar, configurar y probar
```bash
git clone --recurse-submodules <repo> trustronda-n2 && cd trustronda-n2
cp .env.example .env          # completar RPC, PRIVATE_KEY, ETHERSCAN_API_KEY, PRIVATE_KEY_2 y VRF_SUBSCRIPTION_ID
make build && make test && make coverage && make slither
```

## 4. Desplegar y verificar (checklist A)
```bash
make deploy
```
Al terminar debería mostrar `Pass - Verified` para MockUSDC y TrustRondaFactory. Las direcciones quedan en `deployments/11155111.json`.
En vrf.chain.link, la factory tiene que aparecer como **consumer** de tu suscripción. Si `addConsumer` falla, casi siempre es porque la suscripción se creó con otra wallet distinta de `PRIVATE_KEY`.
Si la verificación falla por un timeout, se reintenta solo:
```bash
forge script script/Deploy.s.sol --rpc-url sepolia --resume --verify
```

## 5. Interacción real on-chain (checklist A y F)
```bash
make demo-start
```
Crea una ronda de 2 miembros y la llena con A y B. Con el segundo `join` se pide el sorteo a Chainlink VRF. Imprime la dirección de la ronda. Esperá 1 o 2 minutos: en vrf.chain.link vas a ver el pedido pasar a *fulfilled*. Después:
```bash
make demo-finish RONDA=0x...
```
Juega los 2 turnos en el orden sorteado y hace los retiros; al final muestra `Estado final (3 = Completed): 3`. Si dice que el sorteo todavía no llegó, esperá un poco más y volvé a correrlo.

Verificá la ronda:
```bash
make verify-ronda RONDA=0x...
```

## 6. Completar el README (checklist F)
Reemplazar cada **PENDIENTE** de las secciones 9 y 10:
- Direcciones: `cat deployments/11155111.json`
- Hashes de la demo:
  ```bash
  for f in broadcast/Demo.s.sol/11155111/run-*.json; do jq -r '.transactions[] | "\(.function // .transactionType)  \(.hash)"' "$f"; done
  ```
- URL de cada contrato verificado: `https://sepolia.etherscan.io/address/<DIRECCION>#code`
- URL de cada tx: `https://sepolia.etherscan.io/tx/<HASH>`
- La tx del sorteo no la mandás vos, la manda el oráculo. Buscala en vrf.chain.link, en el detalle de tu suscripción (*Recent fulfillments*), o en Etherscan, en la pestaña *Events* de la factory (`DrawFulfilled`).

Commit sugerido:
```bash
git add README.md deployments/11155111.json broadcast/Deploy.s.sol/11155111/ broadcast/Demo.s.sol/11155111/
git commit -m "docs: agregar direcciones verificadas y transacciones reales de Sepolia"
```
Los archivos de `broadcast/` no tienen secretos (solo direcciones, calldata y hashes) y son evidencia del deploy. Antes de commitear, revisá con `git diff --cached` que no aparezca ninguna private key.

## 7. Frontend
```bash
cd frontend
cp .env.example .env.local      # completar con deployments/11155111.json
npm install && npm run dev
```
**Opcional (suma, checklist H): desplegar en Vercel**
1. vercel.com → Add New Project → importar el repo de GitHub.
2. Root Directory: `frontend`. Framework: Vite (se detecta solo).
3. Environment Variables: las mismas `VITE_*` de `.env.local`.
4. Deploy → copiar la URL en la sección 8 del README.

## 8. Publicar en GitHub (checklist F)
```bash
# en github.com: New repository → "trustronda-n2" → Public, sin README (ya existe)
git remote add origin https://github.com/<TU_USUARIO>/trustronda-n2.git
git push -u origin main
```
Verificar en GitHub que:
- el repo sea **público**;
- los commits aparezcan con **tu cuenta**. El email de los commits es `carlosbinker@gmail.com`; si tu cuenta de GitHub usa otro, agregalo en *Settings → Emails* para que los commits queden asociados;
- **no** esté `.env` y sí `.env.example`.

## 9. Video y whitepaper (checklist G)
**Lo que pidió el profesor en la mentoría (clase 20):**
- El video y el whitepaper se suben a la **carpeta de Drive** de la comisión. Un link en el repo no cumple la consigna.
- El nombre del archivo lleva el **apellido** de quien registró el equipo y el **nombre del proyecto**.
- El whitepaper tiene que incluir un **análisis de viabilidad comercial**: está en la sección 5 de `docs/whitepaper.md`.
- **Fecha:** en la clase 18 Cristian confirmó la entrega el **27/10**, y el enunciado dice martes 27/10 a las 23:59. En la mentoría un alumno dijo "el 25" y nadie lo corrigió, pero vale lo de la clase 18.
- **Entrega individual:** en la clase 18 dijo que hacer el trabajo individual (o pedir prórroga) **solo es posible con una excepción de Talento Tech**. Si todavía no tenés esa autorización por escrito, pedila **ya** (a tu tutora de Talento Tech y a la coordinación de ETH Kipu).

- Grabar siguiendo `docs/guion-video.md` (5:00 como máximo).
- Whitepaper: `docs/whitepaper.md`, exportado a PDF.
- Subir los dos a la carpeta de Drive de la comisión, **con tu apellido en el nombre del archivo**:
  `Binker_TrustRonda_Video.mp4`, `Binker_TrustRonda_Whitepaper.pdf`.
- No tocar archivos de otros grupos (la carpeta es editable por todos).

## 10. Control final
Repasar la tabla de `docs/checklist-entrega.md` ítem por ítem.

## Anexo: ensayo local en anvil (opcional)
Para probar todo sin gastar en Sepolia, con el mock oficial de VRF:
```bash
anvil &                                         # nodo local con cuentas de prueba
cast rpc anvil_mine 5                           # el mock necesita blockhash del bloque anterior
export PRIVATE_KEY=<clave de la cuenta 0 de anvil> PRIVATE_KEY_2=<clave de la cuenta 1>
MOCK=$(forge create lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol:VRFCoordinatorV2_5Mock \
  --rpc-url http://127.0.0.1:8545 --private-key $PRIVATE_KEY --broadcast \
  --constructor-args 100000000000000000 1000000000 4000000000000000 | grep "Deployed to" | awk '{print $3}')
cast send $MOCK "createSubscription()" --rpc-url http://127.0.0.1:8545 --private-key $PRIVATE_KEY
SUB=$(cast call $MOCK "getActiveSubscriptionIds(uint256,uint256)(uint256[])" 0 10 --rpc-url http://127.0.0.1:8545 | tr -d '[]')
cast send $MOCK "fundSubscription(uint256,uint256)" $SUB 1000000000000000000000 --rpc-url http://127.0.0.1:8545 --private-key $PRIVATE_KEY
VRF_COORDINATOR=$MOCK VRF_SUBSCRIPTION_ID=$SUB VRF_KEY_HASH=0x0000000000000000000000000000000000000000000000000000000000000001 \
  forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
forge script script/Demo.s.sol:DemoStart --rpc-url http://127.0.0.1:8545 --broadcast
# hacer de oráculo: requestId = factory.drawRequestOf(ronda)
cast send $MOCK "fulfillRandomWords(uint256,address)" <REQUEST_ID> <FACTORY> --rpc-url http://127.0.0.1:8545 --private-key $PRIVATE_KEY
RONDA=<ronda> forge script script/Demo.s.sol:DemoFinish --rpc-url http://127.0.0.1:8545 --broadcast
```
