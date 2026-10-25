> Salida de `slither . --filter-paths "lib|test|script" --exclude-dependencies --checklist`, **anotada**: cada finding
> marcado como corregido, aceptado (con justificación técnica), falso positivo o fuera de alcance. Los findings
> corregidos (`uninitialized-local`, `unused-return`) ya no aparecen. Detalle en [`../slither.md`](../slither.md).

**THIS CHECKLIST IS NOT COMPLETE**. Use `--show-ignored-findings` to show all the results.
Summary
 - [reentrancy-benign](#reentrancy-benign) (1 results) (Low)
 - [reentrancy-events](#reentrancy-events) (1 results) (Low)
 - [timestamp](#timestamp) (5 results) (Low)
## reentrancy-benign
Impact: Low
Confidence: Medium
 - [x] ID-0 — **ACEPTADO**: el requestId lo genera el coordinador de Chainlink VRF (contrato oficial, dirección `immutable`) y solo se conoce después de la llamada; `requestDraw` solo lo llaman rondas propias, una vez, desde `join()` con `nonReentrant`. Ver docs/slither.md §3.
Reentrancy in [TrustRondaFactory.requestDraw()](contracts/TrustRondaFactory.sol#L220-L238):
	External calls:
	- [requestId = vrfCoordinator.requestRandomWords(VRFV2PlusClient.RandomWordsRequest({keyHash:keyHash,subId:subscriptionId,requestConfirmations:REQUEST_CONFIRMATIONS,callbackGasLimit:CALLBACK_GAS_LIMIT,numWords:NUM_WORDS,extraArgs:VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment:nativePayment}))}))](contracts/TrustRondaFactory.sol#L222-L231)
	State variables written after the call(s):
	- [drawRequestOf[msg.sender] = requestId](contracts/TrustRondaFactory.sol#L233)
	- [drawRequests[requestId] = msg.sender](contracts/TrustRondaFactory.sol#L232)

contracts/TrustRondaFactory.sol#L220-L238


## reentrancy-events
Impact: Low
Confidence: Medium
 - [x] ID-1 — **ACEPTADO**: mismo caso que reentrancy-benign; el evento `DrawRequested` necesita el requestId que devuelve el coordinador. Ver docs/slither.md §4.
Reentrancy in [TrustRondaFactory.requestDraw()](contracts/TrustRondaFactory.sol#L220-L238):
	External calls:
	- [requestId = vrfCoordinator.requestRandomWords(VRFV2PlusClient.RandomWordsRequest({keyHash:keyHash,subId:subscriptionId,requestConfirmations:REQUEST_CONFIRMATIONS,callbackGasLimit:CALLBACK_GAS_LIMIT,numWords:NUM_WORDS,extraArgs:VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment:nativePayment}))}))](contracts/TrustRondaFactory.sol#L222-L231)
	Event emitted after the call(s):
	- [DrawRequested(msg.sender,requestId)](contracts/TrustRondaFactory.sol#L237)

contracts/TrustRondaFactory.sol#L220-L238


## timestamp
Impact: Low
Confidence: Medium
 - [x] ID-2 — **ACEPTADO**: `block.timestamp` se usa solo para plazos de calendario (mínimo 5 min), no para aleatoriedad (eso lo da Chainlink VRF); ningún monto depende del tiempo. Ver docs/slither.md §5-9.
[TrustRonda.cancel()](contracts/TrustRonda.sol#L498-L512) uses timestamp for comparisons
	Dangerous comparisons:
	- [msg.sender != organizer && block.timestamp <= joinDeadline](contracts/TrustRonda.sol#L501)
	- [block.timestamp <= availableAt](contracts/TrustRonda.sol#L506)

contracts/TrustRonda.sol#L498-L512


 - [x] ID-3 — **ACEPTADO**: `block.timestamp` se usa solo para plazos de calendario (mínimo 5 min), no para aleatoriedad (eso lo da Chainlink VRF); ningún monto depende del tiempo. Ver docs/slither.md §5-9.
[MockUSDC.faucet()](contracts/MockUSDC.sol#L38-L46) uses timestamp for comparisons
	Dangerous comparisons:
	- [last != 0 && block.timestamp < last + FAUCET_COOLDOWN](contracts/MockUSDC.sol#L40)

contracts/MockUSDC.sol#L38-L46


 - [x] ID-4 — **ACEPTADO**: `block.timestamp` se usa solo para plazos de calendario (mínimo 5 min), no para aleatoriedad (eso lo da Chainlink VRF); ningún monto depende del tiempo. Ver docs/slither.md §5-9.
[TrustRonda.join()](contracts/TrustRonda.sol#L336-L369) uses timestamp for comparisons
	Dangerous comparisons:
	- [block.timestamp > joinDeadline](contracts/TrustRonda.sol#L338)

contracts/TrustRonda.sol#L336-L369


 - [x] ID-5 — **ACEPTADO**: `block.timestamp` se usa solo para plazos de calendario (mínimo 5 min), no para aleatoriedad (eso lo da Chainlink VRF); ningún monto depende del tiempo. Ver docs/slither.md §5-9.
[TrustRonda.closeRound()](contracts/TrustRonda.sol#L436-L492) uses timestamp for comparisons
	Dangerous comparisons:
	- [paid < n && block.timestamp <= deadline](contracts/TrustRonda.sol#L443)

contracts/TrustRonda.sol#L436-L492


 - [x] ID-6 — **ACEPTADO**: `block.timestamp` se usa solo para plazos de calendario (mínimo 5 min), no para aleatoriedad (eso lo da Chainlink VRF); ningún monto depende del tiempo. Ver docs/slither.md §5-9.
[TrustRonda.contribute()](contracts/TrustRonda.sol#L411-L429) uses timestamp for comparisons
	Dangerous comparisons:
	- [block.timestamp > deadline](contracts/TrustRonda.sol#L416)

contracts/TrustRonda.sol#L411-L429


