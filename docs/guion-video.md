# Guion del video (máximo 5:00)

**Objetivo:** mostrar el proyecto funcionando **de verdad** en Sepolia (checklist G) y tocar cada criterio de evaluación: comprensión técnica, seguridad, calidad, avance, coherencia problema–arquitectura y roadmap.

**Preparación antes de grabar**
- Contratos desplegados y verificados (`make deploy`).
- Dos cuentas de MetaMask en Sepolia (A y B), con ETH de prueba y con el faucet ya usado.
- Una ronda **ya creada, llena y con el orden ya sorteado por Chainlink VRF** con A y B (2 miembros, turnos de 5 minutos), así en el video no se espera al oráculo. Opcional: una segunda ronda recién llena, en estado "Sorteando el orden", para mostrar ese estado.
- La pestaña de tu suscripción en vrf.chain.link, con el pedido de sorteo cumplido (*fulfilled*).
- Pestañas abiertas: la dApp, la factory en Etherscan (pestaña *Contract*, con el tilde verde), VS Code con `TrustRonda.sol` y una terminal en el repo.
- Grabar en 1080p con OBS o la grabación de Meet, y ampliar el zoom del navegador al 125 %.

| Tiempo | Pantalla | Narración (texto sugerido) |
|---|---|---|
| **0:00–0:30** | Portada del README en GitHub | "Soy Carlos Binker y este es TrustRonda, mi proyecto final del Nivel 2. Es una ronda de ahorro, la tanda o pasanaku, pero on-chain. En la ronda tradicional alguien guarda la plata y el que ya cobró puede dejar de pagar. Acá el custodio es un smart contract, el orden de cobro lo sortea Chainlink VRF para que nadie pueda arreglarlo, y si alguien no paga, su garantía cubre el aporte." |
| **0:30–1:15** | Diagrama de arquitectura del README y después VS Code | "Son tres contratos en Foundry con OpenZeppelin 5, integrados con Chainlink VRF. La factory crea cada ronda con `new`. Cuando se completa el cupo, la ronda le pide el sorteo a la factory, la factory se lo pide al coordinador de Chainlink VRF, y cuando el oráculo responde se sortea el orden con Fisher-Yates. La ronda maneja los fondos en tUSD, un stablecoin de prueba de 6 decimales, siempre con SafeERC20. El ciclo es Open, Drawing, Active y Completed." Mostrar el enum y las immutables: "Los parámetros son immutable: nadie puede cambiar las reglas a mitad de la ronda." |
| **1:15–2:00** | VS Code: `join`, `closeRound` y `withdraw` | "Todas las funciones siguen checks-effects-interactions y las que transfieren tienen `nonReentrant`. `closeRound` es el corazón: si alguien no pagó, le ejecuta la garantía y acredita el pozo, pero no transfiere. Usamos pull payments, así nadie puede bloquear la ronda. Los loops están acotados a 12 miembros. Los estados están empaquetados en un solo slot de storage y hay 16 custom errors con parámetros en la ronda, todo con NatSpec completo." |
| **2:00–3:40** | **dApp en vivo** (el momento clave) | 0) Al empezar, una frase: "Uso dos cuentas en la misma wallet para simular a dos miembros; en la realidad, cada uno usa la suya." 1) Con la cuenta A: "Esta es la ronda. En el historial se ve que Chainlink VRF sorteó el orden. La rueda muestra los lugares en ese orden, y el ámbar es el turno actual." (Si preparaste la segunda ronda, mostrá en 5 segundos el estado "Sorteando el orden".) 2) **Pagar aporte**: se ve la firma de approve y contribute en MetaMask y el hash confirmado. 3) Cambiar a la cuenta B y **pagar**. 4) **Cerrar turno**: "Lo puede cerrar cualquiera." 5) Con A, **Retirar** el pozo. 6) Mostrar el **historial on-chain** y abrir uno de los links: "Cada paso es una transacción real en Sepolia." |
| **3:40–4:15** | Terminal: `forge test` y `forge coverage`; después `docs/slither.md` | "Hay 67 tests: unitarios, con el mock oficial de VRF, fuzzing con bound (incluido que el sorteo siempre es una permutación) y una invariante de solvencia que compara el saldo real del token con la contabilidad interna. El coverage da 100 % en todas las métricas. Slither: corregí los dos findings Medium y los siete Low están justificados en el checklist anotado." |
| **4:15–4:35** | Etherscan: el contrato con el tilde verde | "Los contratos están verificados en Sepolia y las direcciones y transacciones están en el README." |
| **4:35–5:00** | Sección Roadmap del README | "Como limitaciones, el cierre de turno es manual y el sorteo depende del saldo de la suscripción de VRF. La fase 2 suma Chainlink Automation para cerrar los turnos solos, garantías dinámicas y una comisión que financie el sorteo. Después, USDC real en una L2, donde el modelo comercial cierra. Gracias." |

**Consejos**
- Cortar los tiempos de espera de confirmación al editar. El enunciado permite editar y narrar con IA, siempre que se vea el funcionamiento real.
- Si algo falla en vivo, el mensaje de error traducido de la dApp también sirve para mostrar el manejo de custom errors.
- Revisar que el video dure **menos de 5:00**. Con 4:45 hay margen. En la clase 19 Cristian dijo que 6 minutos es desaprobado; no conviene pasarse.
- Tiene que verse el flujo **desde el frontend** (clase 19 y mentoría). Las pantallas del NotebookLM sirven como complemento, no como reemplazo.
- Nombre del archivo para el Drive: **`Binker_TrustRonda_Video.mp4`** (lleva el apellido del integrante que registró el grupo).
