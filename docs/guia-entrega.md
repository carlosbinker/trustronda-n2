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

Para exportar una private key en MetaMask: cuenta → ⋮ → Detalles de la cuenta → Mostrar clave privada. **Nunca la pegues en un archivo que se commitee** y nunca uses una wallet con fondos reales.

## 3. Clonar, configurar y probar
```bash
git clone --recurse-submodules <repo> trustronda-n2 && cd trustronda-n2
cp .env.example .env          # completar las 4 variables
make build && make test && make coverage && make slither
```

## 4. Desplegar y verificar (checklist A)
```bash
make deploy
```
Al terminar debería mostrar `Pass - Verified` para MockUSDC y TrustRondaFactory. Las direcciones quedan en `deployments/11155111.json`.
Si la verificación falla por un timeout, se reintenta solo:
```bash
forge script script/Deploy.s.sol --rpc-url sepolia --resume --verify
```

## 5. Interacción real on-chain (checklist A y F)
```bash
make demo
```
Imprime la dirección de la ronda. Verificarla:
```bash
make verify-ronda RONDA=0x...
```

## 6. Completar el README (checklist F)
Reemplazar cada **PENDIENTE** de las secciones 9 y 10:
- Direcciones: `cat deployments/11155111.json`
- Hashes de la demo:
  ```bash
  jq -r '.transactions[] | "\(.function // .transactionType)  \(.hash)"' broadcast/Demo.s.sol/11155111/run-latest.json
  ```
- URL de cada contrato verificado: `https://sepolia.etherscan.io/address/<DIRECCION>#code`
- URL de cada tx: `https://sepolia.etherscan.io/tx/<HASH>`

Commit sugerido:
```bash
git add README.md deployments/11155111.json broadcast/Deploy.s.sol/11155111/run-latest.json broadcast/Demo.s.sol/11155111/run-latest.json
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
- Grabar siguiendo `docs/guion-video.md` (5:00 como máximo).
- Whitepaper: `docs/whitepaper.md`, exportado a PDF.
- Subir los dos a la carpeta de Drive de la comisión, **con tu apellido en el nombre del archivo**:
  `Binker_TrustRonda_Video.mp4`, `Binker_TrustRonda_Whitepaper.pdf`.
- No tocar archivos de otros grupos (la carpeta es editable por todos).

## 10. Control final
Repasar la tabla de `docs/checklist-entrega.md` ítem por ítem.
