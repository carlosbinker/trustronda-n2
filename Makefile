# Atajos del proyecto. Requieren Foundry; slither requiere Python (pip install slither-analyzer).
# Los objetivos que usan la red leen .env (copiar .env.example).
-include .env
export

# Sepolia tiene activo Glamsterdam (06/10/2026): crear contratos y escribir storage cuesta varias veces más gas.
# Sin --hardfork amsterdam, Foundry simula con las reglas viejas, estima de menos y las tx fallan por "out of gas".
SEPOLIA_FLAGS = --hardfork amsterdam --gas-estimate-multiplier 150

.PHONY: install build test test-amsterdam coverage slither slither-checklist deploy demo-start demo-finish verify-ronda abi

install:            ## Submódulos (OpenZeppelin, forge-std) y dependencias del frontend
	git submodule update --init --recursive
	cd frontend && npm install

build:              ## Compila los contratos
	forge build

test:               ## Corre unit + fuzz + invariant
	forge test -vv

test-amsterdam:     ## Los mismos tests con las reglas de gas de Glamsterdam (las que hoy rigen en Sepolia)
	forge test -vv --hardfork amsterdam

coverage:           ## Coverage del código propio (excluye test/ y script/)
	forge coverage --no-match-coverage "(script|test|lib)"

slither:            ## Análisis estático (excluye librerías, tests y scripts)
	slither . --filter-paths "lib|test|script" --exclude-dependencies

slither-checklist:  ## Informe de Slither en formato checklist (como pidió el profesor)
	slither . --filter-paths "lib|test|script" --exclude-dependencies --checklist > docs/reports/slither-checklist-raw.md

deploy:             ## Despliega y verifica MockUSDC + TrustRondaFactory en Sepolia
	forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --verify -vvv $(SEPOLIA_FLAGS)

demo-start:         ## Demo on-chain, paso 1: crea una ronda de 2 y la llena (pide el sorteo a Chainlink VRF)
	forge script script/Demo.s.sol:DemoStart --rpc-url sepolia --broadcast -vvv $(SEPOLIA_FLAGS)

demo-finish:        ## Demo on-chain, paso 2 (después del sorteo): make demo-finish RONDA=0x...
	RONDA=$(RONDA) forge script script/Demo.s.sol:DemoFinish --rpc-url sepolia --broadcast -vvv $(SEPOLIA_FLAGS)

verify-ronda:       ## Verifica una ronda creada por la factory: make verify-ronda RONDA=0x... [BLOCK=bloque de createRonda]
	./script/verify-ronda.sh $(RONDA) $(BLOCK)

abi:                ## Exporta los ABIs al frontend
	forge build
	node frontend/scripts/export-abis.mjs
