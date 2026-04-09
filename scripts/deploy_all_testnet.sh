#!/usr/bin/env bash
# Deploy full stack to Hyperliquid testnet (998) and sync addresses into frontend/.env.local + backend/.env.
# Requires: forge, cast, PRIVATE_KEY + env from deploy/testnet.env.example at repo root.
#
# HyperEVM dual blocks: default "small" blocks have ~3M gas limit; large deployments need "big" blocks (~30M).
# Enable usingBigBlocks for the deployer before broadcasting (see README + HL dual-block architecture docs).
#
# When DEPLOY_USDC_WETH=true, default is a two-phase broadcast so you can switch the deployer from big blocks
# to small blocks (~0.33s) before the second stack — set DEPLOY_PAUSE_BETWEEN_STACKS=0 to use a single `run()`.
#
# Broadcast pacing: by default forge does **not** use `--slow` (faster; txs use sequential nonces in one run).
# If the RPC returns `-32003` / "nonce too high", re-run with: `DEPLOY_SLOW=1 ./scripts/deploy_all_testnet.sh`
# or wait for pending txs to clear (`cast nonce <addr> --rpc-url … --block pending`).
#
# `--rpc-url` + `--fork-block-number` fork HyperEVM for realistic state during simulation.
# HedgeEscrow uses `PrecompileLib.getTokenIndex` (registry) + env spot index (`SPOT_INDEX_*`); the token-info
# precompile (`0x…080C`) used by `getSpotIndex` is not runnable under forge simulation, so the script uses
# env for the spot universe index (must match HL spotMeta / on-chain `getSpotIndex`).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RPC="${TESTNET_RPC_URL:-${RPC_URL:-https://rpc.hyperliquid-testnet.xyz/evm}}"
CHAIN_ID="${CHAIN_ID:-998}"
BROADCAST_DIR="$ROOT/broadcast/DeployAll.s.sol/$CHAIN_ID"
# Used only in two-phase path; must be set under `set -u` so the single-run branch never trips on $SNAP.
SNAP=""
DEPLOY_PAUSE_BETWEEN_STACKS="${DEPLOY_PAUSE_BETWEEN_STACKS:-1}"

# Latest block avoids some RPCs rejecting an implicit fork height (e.g. -32603 invalid block height).
FORK_BLOCK="${FORK_BLOCK:-$(cast block-number --rpc-url "$RPC")}"

FORGE_BASE=(forge script contracts/script/DeployAll.s.sol:DeployAll
  --rpc-url "$RPC"
  --fork-block-number "$FORK_BLOCK"
  --broadcast
)

# DEPLOY_SLOW=1 → --slow (wait for each tx confirmation; use if batched broadcast hits nonce/RPC races)
if [[ "${DEPLOY_SLOW:-}" == "1" ]] || [[ "${DEPLOY_CONCURRENT:-}" == "0" ]]; then
  FORGE_EXTRA=(--slow -vvvv)
else
  FORGE_EXTRA=(-vvvv)
fi

two_phase_weth() {
  [[ "${DEPLOY_USDC_WETH:-}" == "true" ]] && [[ "$DEPLOY_PAUSE_BETWEEN_STACKS" != "0" ]]
}

if two_phase_weth; then
  if [[ ! -t 0 ]]; then
    echo "deploy_all_testnet.sh: two-phase deploy needs an interactive terminal so you can switch to small blocks." >&2
    echo "Run: DEPLOY_PAUSE_BETWEEN_STACKS=0 $0   to broadcast both stacks in one shot (no pause), or use a real TTY." >&2
    exit 1
  fi
  echo "Phase 1/2: USDC/PURR — keep deployer on BIG blocks until this phase finishes."
  "${FORGE_BASE[@]}" --sig 'runStackPurr()' "${FORGE_EXTRA[@]}"

  mkdir -p "$BROADCAST_DIR"
  SNAP="$BROADCAST_DIR/run-after-stack1.json"
  cp "$BROADCAST_DIR/run-latest.json" "$SNAP"

  echo ""
  echo "================================================================================"
  echo "PAUSE: Turn OFF big blocks for this deployer (use small blocks, ~0.33s per block)."
  echo "Then press Enter to run phase 2 (USDC/WETH)."
  echo "================================================================================"
  read -r _

  echo "Phase 2/2: USDC/WETH — small blocks OK for these txs."
  "${FORGE_BASE[@]}" --sig 'runStackWeth()' "${FORGE_EXTRA[@]}"

  export RPC_URL="$RPC"
  export CHAIN_ID
  python3 "$ROOT/scripts/sync_env_from_broadcast.py" --rpc-url "$RPC" --chain-id "$CHAIN_ID" \
    --broadcast-json "$SNAP" \
    --broadcast-json "$BROADCAST_DIR/run-latest.json"
else
  # Default: single `run()` (both stacks in one broadcast if DEPLOY_USDC_WETH=true).
  "${FORGE_BASE[@]}" "${FORGE_EXTRA[@]}"

  export RPC_URL="$RPC"
  export CHAIN_ID
  python3 "$ROOT/scripts/sync_env_from_broadcast.py" --rpc-url "$RPC" --chain-id "$CHAIN_ID"
fi

echo "Done. Restart the Next.js app and backend to pick up new env."
