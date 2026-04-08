#!/usr/bin/env bash
# Deploy full stack to Hyperliquid testnet (998) and sync addresses into frontend/.env.local + backend/.env.
# Requires: forge, PRIVATE_KEY + env from deploy/testnet.env.example at repo root.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RPC="${TESTNET_RPC_URL:-${RPC_URL:-https://rpc.hyperliquid-testnet.xyz/evm}}"
CHAIN_ID="${CHAIN_ID:-998}"

forge script contracts/script/DeployAll.s.sol:DeployAll \
  --rpc-url "$RPC" \
  --broadcast \
  -vvvv

export RPC_URL="$RPC"
export CHAIN_ID
python3 "$ROOT/scripts/sync_env_from_broadcast.py" --rpc-url "$RPC" --chain-id "$CHAIN_ID"

echo "Done. Restart the Next.js app and backend to pick up new env."
