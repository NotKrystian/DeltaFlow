#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -f ".env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source ".env"
  set +a
fi

if [[ -f "frontend/.env.local" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "frontend/.env.local"
  set +a
fi

RPC="${TESTNET_RPC_URL:-${RPC_URL:-https://rpc.hyperliquid-testnet.xyz/evm}}"
POOL="${NEXT_PUBLIC_POOL_WETH:-${NEXT_PUBLIC_POOL:-}}"
VAULT="${NEXT_PUBLIC_VAULT_WETH:-${NEXT_PUBLIC_VAULT:-}}"
USDC="${NEXT_PUBLIC_USDC:-${USDC:-}}"
BASE="${NEXT_PUBLIC_WETH:-${WETH:-}}"
HEDGE_ESCROW="${NEXT_PUBLIC_HEDGE_ESCROW_WETH:-${NEXT_PUBLIC_HEDGE_ESCROW:-}}"
TX_HASH=""
PRETTY=0

POSITION_PRECOMPILE="0x0000000000000000000000000000000000000800"
SPOT_BALANCE_PRECOMPILE="0x0000000000000000000000000000000000000801"
MARK_PX_PRECOMPILE="0x0000000000000000000000000000000000000806"
CORE_USER_EXISTS_PRECOMPILE="0x0000000000000000000000000000000000000810"

TOPIC_TRANSFER="0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
TOPIC_SWAP_HEDGE_EXECUTED="0xe16d293593e29a03fc7e3b7cabc7ceb9ff1700acff6d35e888fea4d30e132a71"
TOPIC_HEDGE_SLICE_QUEUED="0xefeeaffac9ccd1984e1d2a4e3d55bc1b4f60d25b41a353e0852d6aad9c88b9e1"
TOPIC_HEDGE_BATCH_EXECUTED="0xd3c8a0ae1dee0ce7dd0c1c3018d135d99529e0882bf189002838fed822b9578d"
TOPIC_HEDGE_PAYOUT_ESCROWED="0xad4bd961d0cf6ad534be8bd96c11e54a5a11fc8c76e3d4b963d71009538af976"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/debug_hedge_state.sh [--pretty] [tx_hash]

Examples:
  ./scripts/debug_hedge_state.sh
  ./scripts/debug_hedge_state.sh 0xabc...
  ./scripts/debug_hedge_state.sh --pretty 0xabc...
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pretty)
      PRETTY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$TX_HASH" ]]; then
        TX_HASH="$1"
      else
        echo "Unexpected argument: $1" >&2
        usage
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$POOL" || -z "$VAULT" || -z "$USDC" || -z "$BASE" ]]; then
  echo "Missing required env values. Need pool/vault/usdc/base addresses in .env or frontend/.env.local." >&2
  exit 1
fi

trim_cast() {
  awk '{print $1}' <<<"${1:-}"
}

to_block_tag() {
  local blk="${1:-latest}"
  if [[ "$blk" == "latest" ]]; then
    echo "latest"
    return
  fi
  printf "0x%x" "$blk"
}

call_precompile_raw() {
  local to="$1"
  local data="$2"
  local block_tag="${3:-latest}"
  cast rpc eth_call "{\"to\":\"$to\",\"data\":\"$data\"}" "$block_tag" --rpc-url "$RPC" | tr -d '"'
}

decode_position() {
  local raw="$1"
  python3 - "$raw" <<'PY'
import sys
h = sys.argv[1].strip().lower()
if not h or h == "0x":
    print("unavailable")
    raise SystemExit(0)
if h.startswith("0x"):
    h = h[2:]
if len(h) < 64 * 5:
    print("unavailable")
    raise SystemExit(0)
words = [int(h[i:i+64], 16) for i in range(0, 64*5, 64)]
def to_int64(w):
    v = w & ((1 << 64) - 1)
    if v >= (1 << 63):
        v -= (1 << 64)
    return v
szi = to_int64(words[0])
entry_ntl = words[1] & ((1 << 64) - 1)
iso_raw = to_int64(words[2])
lev = words[3] & ((1 << 32) - 1)
isolated = bool(words[4] & 1)
print(f"szi={szi} entryNtl={entry_ntl} isolatedRawUsd={iso_raw} leverage={lev} isIsolated={isolated}")
PY
}

decode_spot_balance() {
  local raw="$1"
  python3 - "$raw" <<'PY'
import sys
h = sys.argv[1].strip().lower()
if not h or h == "0x":
    print("unavailable")
    raise SystemExit(0)
if h.startswith("0x"):
    h = h[2:]
if len(h) < 64 * 3:
    print("unavailable")
    raise SystemExit(0)
words = [int(h[i:i+64], 16) for i in range(0, 64*3, 64)]
total = words[0] & ((1 << 64) - 1)
hold = words[1] & ((1 << 64) - 1)
entry = words[2] & ((1 << 64) - 1)
print(f"total={total} hold={hold} entryNtl={entry}")
PY
}

decode_core_user_exists() {
  local raw="$1"
  python3 - "$raw" <<'PY'
import sys
h = sys.argv[1].strip().lower()
if not h or h == "0x":
    print("unavailable")
    raise SystemExit(0)
if h.startswith("0x"):
    h = h[2:]
if len(h) < 64:
    print("unavailable")
    raise SystemExit(0)
print("true" if (int(h[-64:], 16) & 1) else "false")
PY
}

decode_u64_word() {
  local raw="$1"
  python3 - "$raw" <<'PY'
import sys
h = sys.argv[1].strip().lower()
if not h or h == "0x":
    print("unavailable")
    raise SystemExit(0)
if h.startswith("0x"):
    h = h[2:]
if len(h) < 64:
    print("unavailable")
    raise SystemExit(0)
print(int(h[-16:], 16))
PY
}

read_u256() {
  local addr="$1"
  local sig="$2"
  local block="${3:-latest}"
  trim_cast "$(cast call "$addr" "$sig" --rpc-url "$RPC" --block "$block")"
}

# When debugging a specific tx, Core precompile state should match the block that included it (not `latest`).
TX_BLOCK_TAG="latest"
TX_BLOCK_NUM=""
if [[ -n "${TX_HASH:-}" ]]; then
  if ! RECEIPT_JSON_EARLY="$(cast receipt "$TX_HASH" --rpc-url "$RPC" --json 2>/dev/null)"; then
    echo "Invalid or pending tx hash: $TX_HASH" >&2
    exit 1
  fi
  TX_BLOCK_NUM="$(python3 - "$RECEIPT_JSON_EARLY" <<'PY'
import json, sys
r = json.loads(sys.argv[1])
bn = r["blockNumber"]
print(int(bn, 0) if isinstance(bn, str) else int(bn))
PY
)"
  TX_BLOCK_TAG="$(printf '0x%x' "$TX_BLOCK_NUM")"
fi

BASE_TOKEN_INDEX="${PURR_TOKEN_INDEX:-}"
if [[ -z "$BASE_TOKEN_INDEX" && -n "${HEDGE_ESCROW:-}" ]]; then
  BASE_TOKEN_INDEX="$(trim_cast "$(cast call "$HEDGE_ESCROW" "purrTokenIndex()(uint64)" --rpc-url "$RPC" 2>/dev/null || true)")"
fi

echo "RPC:   $RPC"
echo "POOL:  $POOL"
echo "VAULT: $VAULT"
echo "USDC:  $USDC"
echo "BASE:  $BASE"
[[ -n "$BASE_TOKEN_INDEX" ]] && echo "BASE_TOKEN_INDEX: $BASE_TOKEN_INDEX"
echo ""

echo "== Pool wiring =="
echo "sovereignVault:      $(cast call "$POOL" "sovereignVault()(address)" --rpc-url "$RPC")"
echo "swapFeeModule:       $(cast call "$POOL" "swapFeeModule()(address)" --rpc-url "$RPC")"
echo "swapFeeUpdateTs:     $(cast call "$POOL" "swapFeeModuleUpdateTimestamp()(uint256)" --rpc-url "$RPC")"
echo ""

echo "== Hedge state =="
PERP_INDEX="$(trim_cast "$(cast call "$VAULT" "hedgePerpAssetIndex()(uint32)" --rpc-url "$RPC")")"
echo "hedgePerpAssetIndex: $PERP_INDEX"
echo "useMarkMinHedgeSz:   $(cast call "$VAULT" "useMarkBasedMinHedgeSz()(bool)" --rpc-url "$RPC")"
echo "minPerpHedgeSz:      $(cast call "$VAULT" "minPerpHedgeSz()(uint64)" --rpc-url "$RPC")"
echo "hedgeSzThreshold:    $(cast call "$VAULT" "hedgeSzThreshold()(uint256)" --rpc-url "$RPC")"
echo "pendingBuySz:        $(cast call "$VAULT" "pendingHedgeBuySz()(uint256)" --rpc-url "$RPC")"
echo "pendingSellSz:       $(cast call "$VAULT" "pendingHedgeSellSz()(uint256)" --rpc-url "$RPC")"
echo "pendingBuyWeiDust:   $(cast call "$VAULT" "pendingHedgeBuyWeiDust()(uint256)" --rpc-url "$RPC")"
echo "pendingSellWeiDust:  $(cast call "$VAULT" "pendingHedgeSellWeiDust()(uint256)" --rpc-url "$RPC")"
echo "lastHedgeLeg:        $(cast call "$VAULT" "lastHedgeLeg()(uint8)" --rpc-url "$RPC")"
echo ""

echo "== EVM balances at vault =="
echo "USDC(vault):         $(cast call "$USDC" "balanceOf(address)(uint256)" "$VAULT" --rpc-url "$RPC")"
echo "BASE(vault):         $(cast call "$BASE" "balanceOf(address)(uint256)" "$VAULT" --rpc-url "$RPC")"
echo ""

if [[ -n "$TX_BLOCK_NUM" ]]; then
  echo "== Core precompile reads (end of block $TX_BLOCK_NUM — use this when debugging a tx) =="
else
  echo "== Core precompile reads (latest) =="
fi
MARK_RAW_HEX="$(call_precompile_raw "$MARK_PX_PRECOMPILE" "$(cast abi-encode "foo(uint32)" "$PERP_INDEX")" "$TX_BLOCK_TAG")"
echo "markPx(perp=$PERP_INDEX):     $(decode_u64_word "$MARK_RAW_HEX")"

POS_RAW="$(call_precompile_raw "$POSITION_PRECOMPILE" "$(cast abi-encode "foo(address,uint16)" "$VAULT" "$PERP_INDEX")" "$TX_BLOCK_TAG")"
echo "position(vault,perp):         $(decode_position "$POS_RAW")"

CORE_EXISTS_RAW="$(call_precompile_raw "$CORE_USER_EXISTS_PRECOMPILE" "$(cast abi-encode "foo(address)" "$VAULT")" "$TX_BLOCK_TAG")"
echo "coreUserExists(vault):        $(decode_core_user_exists "$CORE_EXISTS_RAW")"

USDC_SPOT_RAW="$(call_precompile_raw "$SPOT_BALANCE_PRECOMPILE" "$(cast abi-encode "foo(address,uint64)" "$VAULT" 0)" "$TX_BLOCK_TAG")"
echo "spotBalance(vault,USDC=0):    $(decode_spot_balance "$USDC_SPOT_RAW")"

if [[ -n "$BASE_TOKEN_INDEX" ]]; then
  BASE_SPOT_RAW="$(call_precompile_raw "$SPOT_BALANCE_PRECOMPILE" "$(cast abi-encode "foo(address,uint64)" "$VAULT" "$BASE_TOKEN_INDEX")" "$TX_BLOCK_TAG")"
  echo "spotBalance(vault,BASE=$BASE_TOKEN_INDEX): $(decode_spot_balance "$BASE_SPOT_RAW")"
else
  echo "spotBalance(vault,BASE):      unavailable (no BASE token index found)"
fi
echo ""

if [[ -n "$TX_HASH" ]]; then
  RECEIPT_JSON="${RECEIPT_JSON_EARLY:-$(cast receipt "$TX_HASH" --rpc-url "$RPC" --json)}"
  BLOCK_NUM="$(
    python3 - "$RECEIPT_JSON" <<'PY'
import json, sys
r = json.loads(sys.argv[1])
bn = r["blockNumber"]
print(int(bn, 0) if isinstance(bn, str) else int(bn))
PY
  )"
  PRE_BLOCK=$((BLOCK_NUM - 1))

  echo "== Tx summary ($TX_HASH) =="
  cast tx "$TX_HASH" --rpc-url "$RPC"
  echo ""
  echo "== Tx receipt =="
  cast receipt "$TX_HASH" --rpc-url "$RPC"

  if [[ "$PRETTY" == "1" ]]; then
    echo ""
    echo "== Pretty Decode =="
    PRE_PENDING_BUY="$(read_u256 "$VAULT" "pendingHedgeBuySz()(uint256)" "$PRE_BLOCK")"
    POST_PENDING_BUY="$(read_u256 "$VAULT" "pendingHedgeBuySz()(uint256)" "$BLOCK_NUM")"
    PRE_PENDING_SELL="$(read_u256 "$VAULT" "pendingHedgeSellSz()(uint256)" "$PRE_BLOCK")"
    POST_PENDING_SELL="$(read_u256 "$VAULT" "pendingHedgeSellSz()(uint256)" "$BLOCK_NUM")"
    PRE_DUST_BUY="$(read_u256 "$VAULT" "pendingHedgeBuyWeiDust()(uint256)" "$PRE_BLOCK")"
    POST_DUST_BUY="$(read_u256 "$VAULT" "pendingHedgeBuyWeiDust()(uint256)" "$BLOCK_NUM")"
    PRE_DUST_SELL="$(read_u256 "$VAULT" "pendingHedgeSellWeiDust()(uint256)" "$PRE_BLOCK")"
    POST_DUST_SELL="$(read_u256 "$VAULT" "pendingHedgeSellWeiDust()(uint256)" "$BLOCK_NUM")"
    PRE_USDC_BAL="$(trim_cast "$(cast call "$USDC" "balanceOf(address)(uint256)" "$VAULT" --rpc-url "$RPC" --block "$PRE_BLOCK")")"
    POST_USDC_BAL="$(trim_cast "$(cast call "$USDC" "balanceOf(address)(uint256)" "$VAULT" --rpc-url "$RPC" --block "$BLOCK_NUM")")"
    PRE_BASE_BAL="$(trim_cast "$(cast call "$BASE" "balanceOf(address)(uint256)" "$VAULT" --rpc-url "$RPC" --block "$PRE_BLOCK")")"
    POST_BASE_BAL="$(trim_cast "$(cast call "$BASE" "balanceOf(address)(uint256)" "$VAULT" --rpc-url "$RPC" --block "$BLOCK_NUM")")"
    PRE_LEG="$(read_u256 "$VAULT" "lastHedgeLeg()(uint8)" "$PRE_BLOCK")"
    POST_LEG="$(read_u256 "$VAULT" "lastHedgeLeg()(uint8)" "$BLOCK_NUM")"

    python3 - "$RECEIPT_JSON" "$VAULT" "$USDC" "$BASE" \
      "$TOPIC_TRANSFER" "$TOPIC_SWAP_HEDGE_EXECUTED" "$TOPIC_HEDGE_SLICE_QUEUED" \
      "$TOPIC_HEDGE_BATCH_EXECUTED" "$TOPIC_HEDGE_PAYOUT_ESCROWED" <<'PY'
import json, os, sys

receipt = json.loads(sys.argv[1])
vault = sys.argv[2].lower()
usdc = sys.argv[3].lower()
base = sys.argv[4].lower()
topic_transfer = sys.argv[5].lower()
topic_swap = sys.argv[6].lower()
topic_q = sys.argv[7].lower()
topic_b = sys.argv[8].lower()
topic_e = sys.argv[9].lower()

def h2i(x): return int(x, 16)
def topic_addr(t): return "0x" + t[-40:].lower()

logs = receipt.get("logs", [])
usdc_in_to_vault = 0
usdc_out_from_vault = 0
base_in_to_vault = 0
base_out_from_vault = 0

swap_hedges = []
queued = []
batches = []
escrowed = []

for log in logs:
    topics = [t.lower() for t in log.get("topics", [])]
    if not topics:
        continue
    t0 = topics[0]
    addr = log.get("address", "").lower()
    data = log.get("data", "0x")

    if t0 == topic_transfer and len(topics) >= 3:
        frm = topic_addr(topics[1])
        to = topic_addr(topics[2])
        amt = h2i(data)
        if addr == usdc:
            if to == vault: usdc_in_to_vault += amt
            if frm == vault: usdc_out_from_vault += amt
        if addr == base:
            if to == vault: base_in_to_vault += amt
            if frm == vault: base_out_from_vault += amt

    elif t0 == topic_swap and len(topics) >= 3:
        perp = h2i(topics[1])
        side = h2i(topics[2])
        d = data[2:].rjust(128, "0")
        purr_amt = int(d[0:64], 16)
        sz = int(d[64:128], 16)
        swap_hedges.append((perp, side, purr_amt, sz))

    elif t0 == topic_q and len(topics) >= 2:
        buy = h2i(topics[1]) == 1
        d = data[2:].rjust(192, "0")
        sz = int(d[0:64], 16)
        pb = int(d[64:128], 16)
        ps = int(d[128:192], 16)
        queued.append((buy, sz, pb, ps))

    elif t0 == topic_b and len(topics) >= 3:
        perp = h2i(topics[1])
        buy = h2i(topics[2]) == 1
        d = data[2:].rjust(64, "0")
        total_sz = int(d[0:64], 16)
        batches.append((perp, buy, total_sz))

    elif t0 == topic_e and len(topics) >= 3:
        recipient = topic_addr(topics[1])
        token = topic_addr(topics[2])
        d = data[2:].rjust(128, "0")
        amount = int(d[0:64], 16)
        buy = int(d[64:128], 16) == 1
        escrowed.append((recipient, token, amount, buy))

print(f"transfer(usdc): +toVault={usdc_in_to_vault} -fromVault={usdc_out_from_vault}")
print(f"transfer(base): +toVault={base_in_to_vault} -fromVault={base_out_from_vault}")

if swap_hedges:
    for i, (perp, side, purr_amt, sz) in enumerate(swap_hedges, 1):
        direction = "vaultPurrOut=true" if side == 1 else "vaultPurrOut=false"
        print(f"SwapHedgeExecuted[{i}]: perp={perp} {direction} purrAmountWei={purr_amt} sz={sz}")
else:
    print("SwapHedgeExecuted: none")

if queued:
    for i, (buy, sz, pb, ps) in enumerate(queued, 1):
        side = "buyPerp" if buy else "sellPerp"
        print(f"HedgeSliceQueued[{i}]: {side} sz={sz} pendingBuy={pb} pendingSell={ps}")
else:
    print("HedgeSliceQueued: none")

if batches:
    for i, (perp, buy, total_sz) in enumerate(batches, 1):
        side = "buyPerp" if buy else "sellPerp"
        print(f"HedgeBatchExecuted[{i}]: perp={perp} {side} totalSz={total_sz}")
else:
    print("HedgeBatchExecuted: none")

if escrowed:
    for i, (recipient, token, amount, buy) in enumerate(escrowed, 1):
        side = "buyPerpSide" if buy else "sellPerpSide"
        print(f"HedgePayoutEscrowed[{i}]: recipient={recipient} token={token} amount={amount} side={side}")
else:
    print("HedgePayoutEscrowed: none")
PY

    echo ""
    leg_label() {
      case "$1" in
        0) echo "None" ;;
        1) echo "OpenOnly" ;;
        2) echo "UnwindOnly" ;;
        3) echo "UnwindThenOpen" ;;
        *) echo "Unknown($1)" ;;
      esac
    }
    echo "State delta (block $PRE_BLOCK -> $BLOCK_NUM):"
    echo "pendingBuySz:        $PRE_PENDING_BUY -> $POST_PENDING_BUY"
    echo "pendingSellSz:       $PRE_PENDING_SELL -> $POST_PENDING_SELL"
    echo "pendingBuyWeiDust:   $PRE_DUST_BUY -> $POST_DUST_BUY"
    echo "pendingSellWeiDust:  $PRE_DUST_SELL -> $POST_DUST_SELL"
    echo "lastHedgeLeg:        $PRE_LEG ($(leg_label "$PRE_LEG")) -> $POST_LEG ($(leg_label "$POST_LEG"))"
    echo "USDC(vault):         $PRE_USDC_BAL -> $POST_USDC_BAL"
    echo "BASE(vault):         $PRE_BASE_BAL -> $POST_BASE_BAL"

    if [[ -n "$PERP_INDEX" && "$PERP_INDEX" != "0" ]]; then
      PRE_POS_RAW="$(call_precompile_raw "$POSITION_PRECOMPILE" "$(cast abi-encode "foo(address,uint16)" "$VAULT" "$PERP_INDEX")" "$(to_block_tag "$PRE_BLOCK")")"
      POST_POS_RAW="$(call_precompile_raw "$POSITION_PRECOMPILE" "$(cast abi-encode "foo(address,uint16)" "$VAULT" "$PERP_INDEX")" "$(to_block_tag "$BLOCK_NUM")")"
      echo ""
      echo "Perp position (precompile, same blocks as vault delta):"
      echo "  block $PRE_BLOCK: $(decode_position "$PRE_POS_RAW")"
      echo "  block $BLOCK_NUM: $(decode_position "$POST_POS_RAW")"
    fi

    echo ""
    echo "== Interpretation (read with events above) =="
    echo "* lastHedgeLeg: 1=OpenOnly 2=UnwindOnly 3=UnwindThenOpen. Flat perp + sellPerp IOC => OpenOnly SHORT (not closing a long)."
    echo "* HedgeSliceQueued pendingBuy/pendingSell are emitted after enqueue; the same tx often HedgeBatchExecuted and clears pending when totalSz >= hedgeSzThreshold."
    echo "* HedgePayoutEscrowed is the swap tokenOut amount owed to the recipient when the batch pays out — not necessarily 'USDC withdrawn from a closed perp'; bridge/top-up from perp margin happens on other code paths (e.g. immediate hedge or pullPerpUsdcToEvm)."
    echo "* If lastHedgeLeg is OpenOnly on a sellPerp batch, the vault read pos<=0 at IOC time (flat or short). A long would have produced UnwindOnly (2) or UnwindThenOpen (3). If HL UI showed a long, check same vault address + hedgePerpAssetIndex, or a position already closed in an earlier block."
    echo "* Opposite-direction netting (buy vs pending sell or sell vs pending buy) pays _pendingPayouts* via _release*Sz — that path must fund tokenOut from perp/spot like the immediate hedge; batched flush does the same for full-queue payouts."
  fi
fi

