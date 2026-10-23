# Atajos del proyecto. Requieren Foundry; slither requiere Python (pip install slither-analyzer).
# Los objetivos que usan la red leen .env (copiar .env.example).
-include .env
export

.PHONY: install build test coverage slither deploy demo verify-ronda abi anvil-demo

install:            ## Submódulos (OpenZeppelin, forge-std) y dependencias del frontend
	git submodule update --init --recursive
	cd frontend && npm install

build:              ## Compila los contratos
	forge build

test:               ## Corre unit + fuzz + invariant
	forge test -vv

coverage:           ## Coverage del código propio (excluye test/ y script/)
	forge coverage --no-match-coverage "(script|test)"

slither:            ## Análisis estático (excluye librerías, tests y scripts)
	slither . --filter-paths "lib|test|script" --exclude-dependencies

deploy:             ## Despliega y verifica MockUSDC + TrustRondaFactory en Sepolia
	forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --verify -vvv

demo:               ## Ejecuta el flujo principal completo on-chain en Sepolia (2 wallets)
	forge script script/Demo.s.sol --rpc-url sepolia --broadcast -vvv

verify-ronda:       ## Verifica una ronda creada por la factory: make verify-ronda RONDA=0x...
	./script/verify-ronda.sh $(RONDA)

abi:                ## Exporta los ABIs al frontend
	forge build
	node frontend/scripts/export-abis.mjs
