#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RPC="${TESTNET_RPC_URL:-${RPC_URL:-https://rpc.hyperliquid-testnet.xyz/evm}}"
TARGET="${1:-primary}" # primary | weth | both

# Omit fork by default: some HyperEVM RPCs reject `--fork-block-number` for fee estimation / simulation.
# Set FORK_BLOCK explicitly when you need a pinned block for debugging.
FORGE_BASE=(forge script contracts/script/UpgradeFeeModule.s.sol:UpgradeFeeModule
  --rpc-url "$RPC"
  --broadcast
  --slow
  -vvvv
)
if [[ -n "${FORK_BLOCK:-}" ]]; then
  FORGE_BASE+=(--fork-block-number "$FORK_BLOCK")
fi

run_primary() {
  echo "Upgrading fee module for primary pool (EXISTING_POOL)..."
  "${FORGE_BASE[@]}" --sig "runPrimary()"
}

run_weth() {
  echo "Upgrading fee module for WETH pool (EXISTING_POOL_WETH)..."
  "${FORGE_BASE[@]}" --sig "runWeth()"
}

case "$TARGET" in
  primary) run_primary ;;
  weth) run_weth ;;
  both) run_primary; run_weth ;;
  *)
    echo "Usage: $0 [primary|weth|both]" >&2
    exit 1
    ;;
esac

echo "Done. Copy new fee/risk addresses from logs into frontend/.env.local and backend/.env."

