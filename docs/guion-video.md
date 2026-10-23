# Guion del video (máximo 5:00)

**Objetivo:** mostrar el proyecto funcionando **de verdad** en Sepolia (checklist G) y tocar cada criterio de evaluación: comprensión técnica, seguridad, calidad, avance, coherencia problema–arquitectura y roadmap.

**Preparación antes de grabar**
- Contratos desplegados y verificados (`make deploy`).
- Dos cuentas de MetaMask en Sepolia (A y B), con ETH de prueba y con el faucet ya usado.
- Una ronda **ya creada y llena** con A y B (2 miembros, turnos de 5 minutos), así en el video no se espera.
- Pestañas abiertas: la dApp, la factory en Etherscan (pestaña *Contract*, con el tilde verde), VS Code con `TrustRonda.sol` y una terminal en el repo.
- Grabar en 1080p con OBS o la grabación de Meet, y ampliar el zoom del navegador al 125 %.

| Tiempo | Pantalla | Narración (texto sugerido) |
|---|---|---|
| **0:00–0:30** | Portada del README en GitHub | "Soy Carlos Binker y este es TrustRonda, mi proyecto final del Nivel 2. Es una ronda de ahorro, la tanda o pasanaku, pero on-chain. En la ronda tradicional alguien guarda la plata y el que ya cobró puede dejar de pagar. Acá el custodio es un smart contract, y si alguien no paga, su garantía cubre el aporte." |
| **0:30–1:15** | Diagrama de arquitectura del README y después VS Code | "Son tres contratos en Foundry con OpenZeppelin 5. La factory crea cada ronda con `new`: esa es la interacción entre contratos. La ronda maneja los fondos en tUSD, un stablecoin de prueba de 6 decimales, siempre con SafeERC20. El ciclo es Open, Active y Completed." Mostrar el enum y las immutables: "Los parámetros son immutable: nadie puede cambiar las reglas a mitad de la ronda." |
| **1:15–2:00** | VS Code: `join`, `closeRound` y `withdraw` | "Todas las funciones siguen checks-effects-interactions y las que transfieren tienen `nonReentrant`. `closeRound` es el corazón: si alguien no pagó, le ejecuta la garantía y acredita el pozo, pero no transfiere. Usamos pull payments, así nadie puede bloquear la ronda. El único loop está acotado a 12 miembros. Los estados están empaquetados en un solo slot de storage y hay 14 custom errors con parámetros, todo con NatSpec completo." |
| **2:00–3:40** | **dApp en vivo** (el momento clave) | 1) Con la cuenta A: "Esta es la ronda: la rueda muestra los lugares en orden de cobro, y el ámbar es el turno actual." 2) **Pagar aporte**: se ve la firma de approve y contribute en MetaMask y el hash confirmado. 3) Cambiar a la cuenta B y **pagar**. 4) **Cerrar turno**: "Lo puede cerrar cualquiera." 5) Con A, **Retirar** el pozo. 6) Mostrar el **historial on-chain** y abrir uno de los links: "Cada paso es una transacción real en Sepolia." |
| **3:40–4:15** | Terminal: `forge test` y `forge coverage`; después `docs/slither.md` | "Hay 58 tests: unitarios, fuzzing con bound y una invariante de solvencia que compara el saldo real del token con la contabilidad interna. El coverage da 100 % en todas las métricas. Slither encontró una variable sin inicializar, que corregí, y cinco usos de timestamp, que acepté con justificación porque son plazos, no aleatoriedad." |
| **4:15–4:35** | Etherscan: el contrato con el tilde verde | "Los contratos están verificados en Sepolia y las direcciones y transacciones están en el README." |
| **4:35–5:00** | Sección Roadmap del README | "Como limitaciones, el orden es por inscripción y el cierre es manual. La fase 2 suma Chainlink VRF para sortear el orden, Automation para cerrar los turnos solos y garantías dinámicas. Después, USDC real en una L2. Gracias." |

**Consejos**
- Cortar los tiempos de espera de confirmación al editar. El enunciado permite editar y narrar con IA, siempre que se vea el funcionamiento real.
- Si algo falla en vivo, el mensaje de error traducido de la dApp también sirve para mostrar el manejo de custom errors.
- Revisar que el video dure **menos de 5:00**. Con 4:45 hay margen.
- Nombre del archivo para el Drive: **`Binker_TrustRonda_Video.mp4`** (lleva el apellido del integrante que registró el grupo).
