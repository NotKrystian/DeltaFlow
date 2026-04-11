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
# Default deploy path: **first tx only** (`bootstrapFirstTx` = SovereignVault CREATE), then `runAfterFirstTx` /
# `runStackPurr` / etc. **Every** `forge script --broadcast` uses **`--slow`** by default (each tx confirms before
# the next). That avoids `-32003` / `nonce too high` on **the first tx in each multi-tx run** (often shown as
# sequence 1 in the batch) when public RPCs race pending vs latest. Opt out of `--slow` with **`DEPLOY_FAST=1`**
# (or **`DEPLOY_SLOW=0`**). Set **`DEPLOY_SINGLE_SHOT=1`** for one `run()` (legacy).
#
# If errors persist, run `./scripts/check_nonce.sh <deployer>` — latest vs pending mismatch often means mempool /
# RPC split-brain.
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
BOOTSTRAP_JSON="$BROADCAST_DIR/bootstrapFirstTx-latest.json"
RUN_AFTER_JSON="$BROADCAST_DIR/runAfterFirstTx-latest.json"
RUN_STACK_PURR_JSON="$BROADCAST_DIR/runStackPurr-latest.json"
RUN_STACK_WETH_JSON="$BROADCAST_DIR/runStackWeth-latest.json"
# Used only in two-phase path; must be set under `set -u` so the single-run branch never trips on $SNAP.
SNAP=""
DEPLOY_PAUSE_BETWEEN_STACKS="${DEPLOY_PAUSE_BETWEEN_STACKS:-1}"

# Optional fixed fork block. If unset, we refresh to latest before each forge run.
PINNED_FORK_BLOCK="${FORK_BLOCK:-}"

refresh_forge_base() {
  local fork_block
  if [[ -n "$PINNED_FORK_BLOCK" ]]; then
    fork_block="$PINNED_FORK_BLOCK"
  else
    fork_block="$(cast block-number --rpc-url "$RPC")"
  fi
  FORGE_BASE=(forge script contracts/script/DeployAll.s.sol:DeployAll
    --rpc-url "$RPC"
    --fork-block-number "$fork_block"
    --broadcast
  )
  echo "Using fork block: $fork_block"
}

refresh_forge_base

# Default --slow on every broadcast. Opt out: DEPLOY_FAST=1 or DEPLOY_SLOW=0
USE_FAST=0
[[ "${DEPLOY_FAST:-}" == "1" ]] && USE_FAST=1
[[ "${DEPLOY_SLOW:-}" == "0" ]] && USE_FAST=1

if [[ "$USE_FAST" == "1" ]]; then
  FORGE_EXTRA=(-vvvv)
else
  FORGE_EXTRA=(--slow -vvvv)
fi

two_phase_weth() {
  [[ "${DEPLOY_USDC_WETH:-}" == "true" ]] && [[ "$DEPLOY_PAUSE_BETWEEN_STACKS" != "0" ]]
}

deployer_addr() {
  python3 -c '
import json, sys
p = sys.argv[1]
with open(p) as f:
    d = json.load(f)
for t in d.get("transactions", []):
    tx = t.get("transaction") or {}
    frm = tx.get("from") or t.get("from")
    if frm:
        print(frm)
        sys.exit(0)
for r in d.get("receipts", []):
    frm = r.get("from")
    if frm:
        print(frm)
        sys.exit(0)
sys.stderr.write("deploy_all_testnet.sh: could not derive deployer from bootstrap artifact\\n")
sys.exit(1)
' "$BOOTSTRAP_JSON"
}

# Wait until RPC latest nonce catches up to pending nonce for deployer.
# This avoids cross-request nonce races between bootstrapFirstTx and follow-up script runs.
wait_for_nonce_sync() {
  local addr latest pending i
  if ! addr="$(deployer_addr 2>/dev/null)"; then
    echo "deploy_all_testnet.sh: could not derive deployer; skipping nonce sync wait." >&2
    return 0
  fi
  for i in $(seq 1 30); do
    latest="$(cast nonce "$addr" --rpc-url "$RPC" --block latest)"
    pending="$(cast nonce "$addr" --rpc-url "$RPC" --block pending)"
    if [[ "$latest" == "$pending" ]]; then
      echo "Nonce sync OK for $addr (latest=$latest pending=$pending)"
      return 0
    fi
    echo "Waiting for nonce sync for $addr (latest=$latest pending=$pending) ..."
    sleep 2
  done
  echo "deploy_all_testnet.sh: nonce did not sync within timeout; proceeding anyway." >&2
}

# Broadcast SovereignVault only; copies run-latest → run-bootstrap.json and exports SOVEREIGN_VAULT_BOOTSTRAP.
bootstrap_first_tx() {
  mkdir -p "$BROADCAST_DIR"
  refresh_forge_base
  echo "Bootstrap: broadcasting SovereignVault only (first tx) with --slow ..."
  "${FORGE_BASE[@]}" --sig 'bootstrapFirstTx()' --slow -vvvv
  if [[ ! -f "$BOOTSTRAP_JSON" ]]; then
    echo "deploy_all_testnet.sh: expected bootstrap artifact missing: $BOOTSTRAP_JSON" >&2
    exit 1
  fi
  cp "$BOOTSTRAP_JSON" "$BROADCAST_DIR/run-bootstrap.json"
  SOVEREIGN_VAULT_BOOTSTRAP="$(
    python3 -c '
import json, sys
p = sys.argv[1]
with open(p) as f:
    d = json.load(f)
for t in d.get("transactions", []):
    if t.get("contractName") == "SovereignVault" and t.get("contractAddress"):
        print(t["contractAddress"])
        sys.exit(0)
sys.stderr.write("deploy_all_testnet.sh: no SovereignVault in bootstrap broadcast\n")
sys.exit(1)
' "$BOOTSTRAP_JSON"
  )"
  export SOVEREIGN_VAULT_BOOTSTRAP
  echo "SOVEREIGN_VAULT_BOOTSTRAP=$SOVEREIGN_VAULT_BOOTSTRAP"
}

if two_phase_weth; then
  if [[ ! -t 0 ]]; then
    echo "deploy_all_testnet.sh: two-phase deploy needs an interactive terminal so you can switch to small blocks." >&2
    echo "Run: DEPLOY_PAUSE_BETWEEN_STACKS=0 $0   to broadcast both stacks in one shot (no pause), or use a real TTY." >&2
    exit 1
  fi
  echo "Phase 1a/2: USDC/PURR — keep deployer on BIG blocks until PURR stack finishes."
  bootstrap_first_tx
  wait_for_nonce_sync
  refresh_forge_base
  "${FORGE_BASE[@]}" --sig 'runStackPurr()' "${FORGE_EXTRA[@]}"

  PURR_REST="$BROADCAST_DIR/run-after-purr-rest.json"
  if [[ ! -f "$RUN_STACK_PURR_JSON" ]]; then
    echo "deploy_all_testnet.sh: expected runStackPurr artifact missing: $RUN_STACK_PURR_JSON" >&2
    exit 1
  fi
  cp "$RUN_STACK_PURR_JSON" "$PURR_REST"

  echo ""
  echo "================================================================================"
  echo "PAUSE: Turn OFF big blocks for this deployer (use small blocks, ~0.33s per block)."
  echo "Then press Enter to run phase 2 (USDC/WETH)."
  echo "================================================================================"
  read -r _

  echo "Phase 2/2: USDC/WETH — small blocks OK for these txs."
  refresh_forge_base
  "${FORGE_BASE[@]}" --sig 'runStackWeth()' "${FORGE_EXTRA[@]}"

  export RPC_URL="$RPC"
  export CHAIN_ID
  python3 "$ROOT/scripts/sync_env_from_broadcast.py" --rpc-url "$RPC" --chain-id "$CHAIN_ID" \
    --broadcast-json "$BOOTSTRAP_JSON" \
    --broadcast-json "$PURR_REST" \
    --broadcast-json "$RUN_STACK_WETH_JSON"
elif [[ "${DEPLOY_SINGLE_SHOT:-}" == "1" ]]; then
  echo "DEPLOY_SINGLE_SHOT=1: single forge run() (no bootstrap split)."
  refresh_forge_base
  "${FORGE_BASE[@]}" "${FORGE_EXTRA[@]}"

  export RPC_URL="$RPC"
  export CHAIN_ID
  python3 "$ROOT/scripts/sync_env_from_broadcast.py" --rpc-url "$RPC" --chain-id "$CHAIN_ID"
else
  # Default: first tx alone (--slow), then runAfterFirstTx (FORGE_EXTRA defaults to --slow).
  bootstrap_first_tx
  wait_for_nonce_sync
  refresh_forge_base
  "${FORGE_BASE[@]}" --sig 'runAfterFirstTx()' "${FORGE_EXTRA[@]}"
  if [[ ! -f "$RUN_AFTER_JSON" ]]; then
    echo "deploy_all_testnet.sh: expected runAfterFirstTx artifact missing: $RUN_AFTER_JSON" >&2
    exit 1
  fi

  export RPC_URL="$RPC"
  export CHAIN_ID
  python3 "$ROOT/scripts/sync_env_from_broadcast.py" --rpc-url "$RPC" --chain-id "$CHAIN_ID" \
    --broadcast-json "$BOOTSTRAP_JSON" \
    --broadcast-json "$RUN_AFTER_JSON"
fi

echo "Done. Restart the Next.js app and backend to pick up new env."
