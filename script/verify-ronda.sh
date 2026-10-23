#!/usr/bin/env bash
# Verifica en Etherscan una ronda TrustRonda creada por la factory.
# Las rondas se despliegan con `new` desde TrustRondaFactory, así que `forge script --verify` no las verifica solas.
# Este script reconstruye los argumentos del constructor leyendo los getters on-chain y el bloque de creación.
#
# Uso:  ./script/verify-ronda.sh <DIRECCION_RONDA>
# Requiere en .env: SEPOLIA_RPC_URL y ETHERSCAN_API_KEY
set -euo pipefail
source .env

RONDA="${1:?Uso: ./script/verify-ronda.sh <DIRECCION_RONDA>}"
RPC="$SEPOLIA_RPC_URL"
FACTORY=$(jq -r '.TrustRondaFactory' deployments/11155111.json)
FROM_BLOCK=$(jq -r '.deployBlock' deployments/11155111.json)

ORGANIZER=$(cast call "$RONDA" "organizer()(address)" --rpc-url "$RPC")
TOKEN=$(cast call "$RONDA" "token()(address)" --rpc-url "$RPC")
CONTRIB=$(cast call "$RONDA" "contributionAmount()(uint256)" --rpc-url "$RPC" | awk '{print $1}')
COLLAT=$(cast call "$RONDA" "collateralAmount()(uint256)" --rpc-url "$RPC" | awk '{print $1}')
MAXM=$(cast call "$RONDA" "maxMembers()(uint8)" --rpc-url "$RPC")
ROUNDD=$(cast call "$RONDA" "roundDuration()(uint64)" --rpc-url "$RPC" | awk '{print $1}')
JOINDL=$(cast call "$RONDA" "joinDeadline()(uint64)" --rpc-url "$RPC" | awk '{print $1}')

# joinWindow = joinDeadline - timestamp del bloque en que la factory creó la ronda (evento RondaCreated)
TOPIC=$(cast keccak "RondaCreated(address,address,address,uint256,uint256,uint8,uint64,uint64)")
RONDA_TOPIC=$(cast abi-encode "f(address)" "$RONDA")
BLOCK=$(cast logs --from-block "$FROM_BLOCK" --address "$FACTORY" "$TOPIC" "$RONDA_TOPIC" --rpc-url "$RPC" --json | jq -r '.[0].blockNumber')
TS=$(cast block "$BLOCK" --field timestamp --rpc-url "$RPC")
JOINW=$((JOINDL - TS))

ARGS=$(cast abi-encode "constructor(address,address,uint256,uint256,uint8,uint64,uint64)" \
  "$ORGANIZER" "$TOKEN" "$CONTRIB" "$COLLAT" "$MAXM" "$ROUNDD" "$JOINW")

echo "Verificando TrustRonda $RONDA (joinWindow = $JOINW s)"
forge verify-contract "$RONDA" contracts/TrustRonda.sol:TrustRonda \
  --chain sepolia --constructor-args "$ARGS" --etherscan-api-key "$ETHERSCAN_API_KEY" --watch
