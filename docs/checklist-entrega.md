# Checklist de entrega: estado

Estado al 25/10/2026, con los contratos desplegados y verificados en Sepolia y la demo on-chain completa. ✅ hecho y verificado · ⏳ depende del deploy, la grabación o la publicación (lo hace Carlos) · ➖ no aplica.

## A. Funcionalidad y smart contracts
| Ítem | Estado | Evidencia |
|---|---|---|
| Pertinente para Web3 | ✅ | README §1, whitepaper §1–2 |
| Flujo principal de punta a punta | ✅ | `test_FullCycle_AllPay_EveryoneEndsEven`, `Demo.s.sol`, e2e del frontend en anvil |
| Hardhat o Foundry | ✅ | Foundry (`foundry.toml`) |
| Al menos una interacción entre contratos | ✅ | Factory → `new TrustRonda`; TrustRonda → Factory → **Chainlink VRF Coordinator** (externo) → Factory → TrustRonda; TrustRonda → ERC20 con SafeERC20. On-chain: tx 3, 7 y 8 de la sección 10 del README |
| Todos los contratos propios desplegados | ✅ | MockUSDC, TrustRondaFactory y una TrustRonda en Sepolia (README, sección 9; `deployments/11155111.json`) |
| Verificados, con URL en el README | ✅ | Los tres en Etherscan y Sourcify (Exact Match en la factory y la ronda), con links en la sección 9 del README |
| Desplegado = código del repo | ✅ | Sourcify da Exact Match contra `contracts/` (mismo fuente, compilador y metadata); los commits posteriores al deploy no tocan los contratos |
| Interacción real on-chain | ✅ | 21 tx de la demo, incluida la respuesta de VRF (dos turnos completos, ronda `Completed` con saldo 0) en la sección 10 del README y en `broadcast/Demo.s.sol/11155111/` |

## B. Calidad del código Solidity
| Ítem | Estado | Evidencia |
|---|---|---|
| NatSpec completo | ✅ | Variables, structs, eventos y sus parámetros, errores y sus parámetros, modifiers, funciones con `@param`/`@return`, roles en `@dev` |
| Custom errors | ✅ | 16 + 5 + 1, con parámetros |
| Sin strings ni bytes largos | ✅ | — |
| Sin lecturas o escrituras repetidas de storage | ✅ | Variables locales cacheadas; slots empaquetados |
| storage / memory / calldata | ✅ | `MemberInfo storage`; `memory` en las views |
| constant / immutable | ✅ | 4 constants + 7 immutables en TrustRonda |
| Visibilidad y mutabilidad | ✅ | external / internal view / pure |
| Eventos en operaciones relevantes | ✅ | 11 + 4 + 1 eventos |
| CEI | ✅ | join, contribute, withdraw; closeRound sin llamadas externas |
| Control de acceso y roles en NatSpec | ✅ | `@dev Roles y privilegios` en los dos contratos |
| SafeERC20 | ✅ | Todas las transferencias |
| Sin estado o cálculos innecesarios | ✅ | — |
| Nombres claros y orden de la clase 3 | ✅ | — |
| Sin tx.origin, delegatecall, selfdestruct ni assembly | ✅ | `grep` sin resultados |
| unchecked seguro | ✅ | Solo contadores acotados por 12, con comentario |
| Proxies | ➖ | No se usan (decisión de diseño, ver la explicación) |

## C. Testing
| Ítem | Estado | Evidencia |
|---|---|---|
| 100 % de los tests pasa | ✅ | 70/70, `docs/reports/forge-test.txt` |
| Test del flujo exitoso | ✅ | `test_FullCycle_*`, fuzz |
| Test de revert | ✅ | 34 tests `test_RevertWhen_*` |
| Coverage > 40 % en todas las métricas | ✅ | 100 / 100 / 100 / 100, `docs/reports/coverage.txt` |

## D. Slither
| Ítem | Estado | Evidencia |
|---|---|---|
| Ejecutado sobre el contrato principal | ✅ | Sobre los 3 contratos |
| Findings necesarios corregidos | ✅ | `uninitialized-local`, `unused-return` |
| Findings restantes clasificados | ✅ | 7 Low aceptados, anotados en `docs/reports/slither-checklist.md` |
| Justificación de los aceptados | ✅ | `docs/slither.md` |
| Ningún problema relevante sin corregir | ✅ | Sin High ni Medium |

## E. Frontend y demo
| Ítem | Estado | Evidencia |
|---|---|---|
| Hay un frontend | ✅ | `/frontend` |
| Interactúa con los contratos y muestra el flujo | ✅ | e2e con Playwright en anvil: flujo completo |
| Evidencia real on-chain en la demo | ✅ | Ronda `0x0131…1B16` jugada desde la dApp en Sepolia, con un impago cubierto por la garantía (README, sección 10); falta grabar el video |
| Complejidad acorde | ✅ | Factory + máquina de estados + garantías + fuzz/invariant |
| Claro y funcional antes que complejo | ✅ | VRF implementado (lo pidió el profesor); Automation queda en el roadmap |

## F. Repositorio y documentación
| Ítem | Estado | Evidencia |
|---|---|---|
| Repo público | ✅ | `github.com/carlosbinker/trustronda-n2` |
| Commit con la cuenta propia | ⏳ | Commits con `carlosbinker@gmail.com`; confirmar que el email esté en la cuenta de GitHub |
| Cero secretos | ✅ | `.env` en `.gitignore`; revisado con `git ls-files` |
| `.env.example` | ✅ | Raíz y `frontend/` |
| Compila sin warnings sin analizar | ✅ | 0 warnings; los analizados están en README §12 |
| README con los 10 puntos mínimos | ✅ | Completo, con direcciones, links de verificación y hashes reales (secciones 9 y 10) |

## G. Video
| Ítem | Estado | Evidencia |
|---|---|---|
| ≤ 5 minutos | ⏳ | `Binker_TrustRonda_Video.mp4` (entregado en el Drive) |
| Muestra el funcionamiento real | ⏳ | Flujo completo desde el frontend, en vivo en Sepolia |

## Indicaciones del profesor (clases 19 y 20)
| Ítem | Estado | Evidencia |
|---|---|---|
| Chainlink VRF para el sorteo (mentoría 0:33:44) | ✅ | `TrustRondaFactory.requestDraw` / `rawFulfillRandomWords`, `TrustRonda.fulfillDraw` |
| Whitepaper con viabilidad comercial (mentoría 0:14:06) | ✅ | `docs/whitepaper.md` §5 |
| Slither con `--checklist` y findings anotados (mentoría 0:58:56) | ✅ | `docs/reports/slither-checklist.md` |
| Un solo repo con contratos y frontend | ✅ | `/contracts` + `/frontend` |
| Video y whitepaper en el Drive, con apellido y nombre del proyecto | ⏳ | `Binker_TrustRonda_*` |
| Sin Remix como herramienta de desarrollo (clase 19) | ✅ | Foundry |
| Entrega individual: requiere excepción de Talento Tech (clase 18) | ✅ | Autorizada por Talento Tech el 25/10/2026 |
| Fecha 27/10 (confirmada en la clase 18) | ✅ | — |

## H. Opcional
| Ítem | Estado | Evidencia |
|---|---|---|
| Frontend desplegado | ⏳ | Vercel (pendiente); hoy se corre local con `npm run dev` |
