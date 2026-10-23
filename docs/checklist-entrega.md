# Checklist de entrega: estado

Estado al cerrar el código (23/10/2026). ✅ hecho y verificado · ⏳ depende del deploy, la grabación o la publicación (lo hace Carlos) · ➖ no aplica.

## A. Funcionalidad y smart contracts
| Ítem | Estado | Evidencia |
|---|---|---|
| Pertinente para Web3 | ✅ | README §1, whitepaper §1–2 |
| Flujo principal de punta a punta | ✅ | `test_FullCycle_AllPay_EveryoneEndsEven`, `Demo.s.sol`, e2e del frontend en anvil |
| Hardhat o Foundry | ✅ | Foundry (`foundry.toml`) |
| Al menos una interacción entre contratos | ✅ | Factory → `new TrustRonda`; TrustRonda → ERC20 con SafeERC20 |
| Todos los contratos propios desplegados | ⏳ | `make deploy` + `make demo` |
| Verificados, con URL en el README | ⏳ | `--verify` + `make verify-ronda`; completar README §9 |
| Desplegado = código del repo | ⏳ | Desplegar desde el commit final, sin cambios locales |
| Interacción real on-chain | ⏳ | `make demo` y la demo del video; completar README §10 |

## B. Calidad del código Solidity
| Ítem | Estado | Evidencia |
|---|---|---|
| NatSpec completo | ✅ | Variables, structs, eventos y sus parámetros, errores y sus parámetros, modifiers, funciones con `@param`/`@return`, roles en `@dev` |
| Custom errors | ✅ | 14 + 2 + 1, con parámetros |
| Sin strings ni bytes largos | ✅ | — |
| Sin lecturas o escrituras repetidas de storage | ✅ | Variables locales cacheadas; slots empaquetados |
| storage / memory / calldata | ✅ | `MemberInfo storage`; `memory` en las views |
| constant / immutable | ✅ | 4 constants + 7 immutables en TrustRonda |
| Visibilidad y mutabilidad | ✅ | external / internal view / pure |
| Eventos en operaciones relevantes | ✅ | 9 + 2 + 1 eventos |
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
| 100 % de los tests pasa | ✅ | 58/58, `docs/reports/forge-test.txt` |
| Test del flujo exitoso | ✅ | `test_FullCycle_*`, fuzz |
| Test de revert | ✅ | 29 tests `test_RevertWhen_*` |
| Coverage > 40 % en todas las métricas | ✅ | 100 / 100 / 100 / 100, `docs/reports/coverage.txt` |

## D. Slither
| Ítem | Estado | Evidencia |
|---|---|---|
| Ejecutado sobre el contrato principal | ✅ | Sobre los 3 contratos |
| Findings necesarios corregidos | ✅ | `uninitialized-local` |
| Findings restantes clasificados | ✅ | 5 × `timestamp` aceptados |
| Justificación de los aceptados | ✅ | `docs/slither.md` |
| Ningún problema relevante sin corregir | ✅ | Sin High ni Medium |

## E. Frontend y demo
| Ítem | Estado | Evidencia |
|---|---|---|
| Hay un frontend | ✅ | `/frontend` |
| Interactúa con los contratos y muestra el flujo | ✅ | e2e con Playwright en anvil: flujo completo |
| Evidencia real on-chain en la demo | ⏳ | Historial con links a Etherscan; grabar en Sepolia |
| Complejidad acorde | ✅ | Factory + máquina de estados + garantías + fuzz/invariant |
| Claro y funcional antes que complejo | ✅ | VRF y Automation quedan en el roadmap |

## F. Repositorio y documentación
| Ítem | Estado | Evidencia |
|---|---|---|
| Repo público | ⏳ | Crear en GitHub y hacer push |
| Commit con la cuenta propia | ⏳ | Commits con `carlosbinker@gmail.com`; confirmar que el email esté en la cuenta de GitHub |
| Cero secretos | ✅ | `.env` en `.gitignore`; revisado con `git ls-files` |
| `.env.example` | ✅ | Raíz y `frontend/` |
| Compila sin warnings sin analizar | ✅ | 0 warnings; los analizados están en README §12 |
| README con los 10 puntos mínimos | ✅ / ⏳ | Completo; faltan direcciones y hashes reales (§9 y §10) |

## G. Video
| Ítem | Estado | Evidencia |
|---|---|---|
| ≤ 5 minutos | ⏳ | Guion de 5:00 en `docs/guion-video.md` |
| Muestra el funcionamiento real | ⏳ | Segmento 2:00–3:40 en vivo en Sepolia |

## H. Opcional
| Ítem | Estado | Evidencia |
|---|---|---|
| Frontend desplegado | ⏳ | Vercel, ver `docs/guia-entrega.md` §7 |
