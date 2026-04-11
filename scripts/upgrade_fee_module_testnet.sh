#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RPC="${TESTNET_RPC_URL:-${RPC_URL:-https://rpc.hyperliquid-testnet.xyz/evm}}"
FORK_BLOCK="${FORK_BLOCK:-$(cast block-number --rpc-url "$RPC")}"
TARGET="${1:-primary}" # primary | weth | both

FORGE_BASE=(forge script contracts/script/UpgradeFeeModule.s.sol:UpgradeFeeModule
  --rpc-url "$RPC"
  --fork-block-number "$FORK_BLOCK"
  --broadcast
  --slow
  -vvvv
)

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

