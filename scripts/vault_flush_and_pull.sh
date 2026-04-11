#!/usr/bin/env bash
# Flush batched hedge queues to EVM, then pull USDC from perp margin and base from HyperCore spot into the vault.
#
# Does NOT close open perp positions (no on-chain "market close all" here). After pulls, close any
# remaining szi via Hyperliquid (testnet) against the vault address, or reduce-only IOCs, then re-run pulls.
#
# Optional: strategist-only Core lending recovery — see docs comment at bottom.
#
# Usage:
#   ./scripts/vault_flush_and_pull.sh
#   VAULT=0x... ./scripts/vault_flush_and_pull.sh
#
# Requires: cast (Foundry), PRIVATE_KEY with HYPE for gas, .env or frontend/.env.local with RPC + addresses.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -f ".env" ]]; then set -a && source ".env" && set +a; fi
if [[ -f "frontend/.env.local" ]]; then set -a && source "frontend/.env.local" && set +a; fi

RPC="${TESTNET_RPC_URL:-${RPC_URL:-https://rpc.hyperliquid-testnet.xyz/evm}}"
VAULT="${VAULT:-${NEXT_PUBLIC_VAULT_WETH:-${NEXT_PUBLIC_VAULT:-}}}"
USDC="${USDC:-${NEXT_PUBLIC_USDC:-}}"
BASE="${BASE:-${NEXT_PUBLIC_WETH:-${WETH:-}}}"

# Pull caps (EVM raw units): USDC uses 6 decimals, BASE typically 18. Increase if you hit the cap.
# Default USDC: 10^13 raw = 10M USDC. Default BASE: 10^24 raw = 1M tokens @ 18 decimals.
MAX_PULL_USDC_WEI="${MAX_PULL_USDC_WEI:-10000000000000}"
MAX_PULL_BASE_WEI="${MAX_PULL_BASE_WEI:-1000000000000000000000000}"

if [[ -z "${PRIVATE_KEY:-}" ]]; then
  echo "PRIVATE_KEY missing in .env" >&2
  exit 1
fi
if [[ -z "$VAULT" || -z "$USDC" || -z "$BASE" ]]; then
  echo "Need VAULT, USDC, BASE (set env or NEXT_PUBLIC_* in .env.local)." >&2
  exit 1
fi

echo "RPC:   $RPC"
echo "VAULT: $VAULT"
echo ""

echo "== Before: pending hedge sz =="
echo "pendingHedgeBuySz:  $(cast call "$VAULT" "pendingHedgeBuySz()(uint256)" --rpc-url "$RPC")"
echo "pendingHedgeSellSz: $(cast call "$VAULT" "pendingHedgeSellSz()(uint256)" --rpc-url "$RPC")"
echo ""

echo "== 1) forceFlushHedgeBatch() — pays escrowed swap tokenOuts for queued sz (permissionless) =="
cast send "$VAULT" "forceFlushHedgeBatch()" --rpc-url "$RPC" --private-key "$PRIVATE_KEY"
echo ""

echo "== After flush: pending =="
echo "pendingHedgeBuySz:  $(cast call "$VAULT" "pendingHedgeBuySz()(uint256)" --rpc-url "$RPC")"
echo "pendingHedgeSellSz: $(cast call "$VAULT" "pendingHedgeSellSz()(uint256)" --rpc-url "$RPC")"
echo ""

echo "== 2) pullPerpUsdcToEvm(max) — move USDC from perp class toward EVM (permissionless) =="
cast send "$VAULT" "pullPerpUsdcToEvm(uint256)" "$MAX_PULL_USDC_WEI" --rpc-url "$RPC" --private-key "$PRIVATE_KEY"
echo ""

echo "== 3) pullCoreSpotTokenToEvm(base, max) — bridge linked spot base to HyperEVM vault =="
cast send "$VAULT" "pullCoreSpotTokenToEvm(address,uint256)" "$BASE" "$MAX_PULL_BASE_WEI" --rpc-url "$RPC" --private-key "$PRIVATE_KEY"
echo ""

echo "== Vault EVM token balances (rough) =="
echo "USDC: $(cast call "$USDC" "balanceOf(address)(uint256)" "$VAULT" --rpc-url "$RPC")"
echo "BASE: $(cast call "$BASE" "balanceOf(address)(uint256)" "$VAULT" --rpc-url "$RPC")"
echo ""
echo "Done on-chain flush + pull. Next steps (manual):"
echo "  • Check perp still open: ./scripts/debug_hedge_state.sh  (see position(vault,perp))"
echo "  • If szi != 0: close on Hyperliquid testnet for the vault address (API wallet / agent), then run this script again for pulls."
echo "  • If USDC sits in Core lending vaults: strategist calls deallocate(coreVault, amount) on SovereignVault, then bridgeToEvmOnly if needed."
echo "  • LP withdrawal: use withdrawLP on vault as an LP, not this script."
