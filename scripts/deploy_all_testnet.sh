#!/usr/bin/env bash
# Deploy full stack to Hyperliquid testnet (998) and sync addresses into frontend/.env.local + backend/.env.
# Requires: forge, cast, PRIVATE_KEY + env from deploy/testnet.env.example at repo root.
#
# HedgeEscrow wiring calls HyperEVM precompiles (registry + token info). Forge must simulate against a fork
# of HyperEVM (`--fork-url` + `--fork-block-number`); a plain local EVM reverts on precompile 0x…080C.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RPC="${TESTNET_RPC_URL:-${RPC_URL:-https://rpc.hyperliquid-testnet.xyz/evm}}"
CHAIN_ID="${CHAIN_ID:-998}"

# Latest block avoids some RPCs rejecting an implicit fork height (e.g. -32603 invalid block height).
FORK_BLOCK="${FORK_BLOCK:-$(cast block-number --rpc-url "$RPC")}"

forge script contracts/script/DeployAll.s.sol:DeployAll \
  --rpc-url "$RPC" \
  --fork-url "$RPC" \
  --fork-block-number "$FORK_BLOCK" \
  --broadcast \
  -vvvv

export RPC_URL="$RPC"
export CHAIN_ID
python3 "$ROOT/scripts/sync_env_from_broadcast.py" --rpc-url "$RPC" --chain-id "$CHAIN_ID"

echo "Done. Restart the Next.js app and backend to pick up new env."
