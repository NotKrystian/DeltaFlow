#!/usr/bin/env bash
# Verify on-chain wiring against env or defaults (Hyperliquid testnet 998).
# Override: POOL=... VAULT=... ALM=... SWAP_FEE_MODULE=... DEPLOYER=...
set -euo pipefail

RPC="${RPC_URL:-https://rpc.hyperliquid-testnet.xyz/evm}"

# Defaults match frontend/src/contracts.ts placeholders — replace after deploy.
POOL="${POOL:-0x2E5bB169b596b3136C717258b40D6F83Ae5393Fd}"
VAULT="${VAULT:-0x715EB367788e71C4c6aee4E8994aD407807fec27}"
ALM="${ALM:-0x773ACA23c3B9E9EB8e7BD27Da3863957B66e9526}"
FEE="${SWAP_FEE_MODULE:-0xA0Fa62675a8Db6814510eEF716c67021F249a5d6}"

PURR="${PURR_TOKEN:-0xa9056c15938f9aff34CD497c722Ce33dB0C2fD57}"
USDC="${USDC_TOKEN:-0x2B3370eE501B4a559b57D449569354196457D8Ab}"
# Wallet that broadcast the deploy (SovereignVault.strategist == msg.sender of vault deploy)
DEPLOYER="${DEPLOYER:-0x13e00D9810d3C8Dc19A8C9A172fd9A8aC56e94e0}"
POOL_MANAGER="${POOL_MANAGER:-$DEPLOYER}"

norm() { echo "$1" | tr '[:upper:]' '[:lower:]'; }

call_addr() {
  local addr="$1" sig="$2"
  cast call "$addr" "$sig" --rpc-url "$RPC" 2>/dev/null | head -n 1
}

call_bool() {
  local addr="$1" sig="$2" arg="$3"
  cast call "$addr" "$sig" "$arg" --rpc-url "$RPC" 2>/dev/null | head -n 1
}

expect_eq() {
  local label="$1" got="$2" exp="$3"
  if [[ "$(norm "$got")" == "$(norm "$exp")" ]]; then
    echo "✅ PASS  $label"
  else
    echo "❌ FAIL  $label"
    echo "        got: $got"
    echo "        exp: $exp"
    exit 1
  fi
}

expect_true() {
  local label="$1" got="$2"
  if [[ "$got" == "true" || "$got" == "1" ]]; then
    echo "✅ PASS  $label"
  else
    echo "❌ FAIL  $label"
    echo "        got: $got"
    echo "        exp: true"
    exit 1
  fi
}

echo "RPC: $RPC"
echo "POOL: $POOL"
echo "VAULT: $VAULT"
echo "ALM: $ALM"
echo "SWAP_FEE_MODULE: $FEE"
echo

t0=$(call_addr "$POOL" "token0()(address)")
t1=$(call_addr "$POOL" "token1()(address)")
sv=$(call_addr "$POOL" "sovereignVault()(address)")
alm=$(call_addr "$POOL" "alm()(address)")
sfm=$(call_addr "$POOL" "swapFeeModule()(address)")
pm=$(call_addr "$POOL" "poolManager()(address)")

expect_eq "Pool.token0 == PURR" "$t0" "$PURR"
expect_eq "Pool.token1 == USDC" "$t1" "$USDC"
expect_eq "Pool.sovereignVault == Vault" "$sv" "$VAULT"
expect_eq "Pool.alm == ALM" "$alm" "$ALM"
expect_eq "Pool.swapFeeModule == SWAP_FEE_MODULE" "$sfm" "$FEE"
expect_eq "Pool.poolManager == DEPLOYER" "$pm" "$DEPLOYER"

echo

v_usdc=$(call_addr "$VAULT" "usdc()(address)")
v_strat=$(call_addr "$VAULT" "strategist()(address)")
v_auth=$(call_bool "$VAULT" "authorizedPools(address)(bool)" "$POOL")

expect_eq "Vault.usdc == USDC" "$v_usdc" "$USDC"
expect_eq "Vault.strategist == deployer wallet" "$v_strat" "$DEPLOYER"
expect_true "Vault.authorizedPools(POOL) == true" "$v_auth"

echo

alm_pool=$(call_addr "$ALM" "pool()(address)" || true)
if [[ -z "${alm_pool:-}" ]]; then
  alm_pool=$(call_addr "$ALM" "sovereignPool()(address)" || true)
fi
if [[ -z "${alm_pool:-}" ]]; then
  alm_pool=$(call_addr "$ALM" "SOVEREIGN_POOL()(address)" || true)
fi

if [[ -n "${alm_pool:-}" ]]; then
  expect_eq "ALM.pool == POOL" "$alm_pool" "$POOL"
else
  echo "⚠️  ALM check skipped: couldn't find pool()/sovereignPool()/SOVEREIGN_POOL() getter."
fi

echo

fee_pool=$(call_addr "$FEE" "pool()(address)" || true)
if [[ -z "${fee_pool:-}" ]]; then
  fee_pool=$(call_addr "$FEE" "sovereignPool()(address)" || true)
fi

if [[ -n "${fee_pool:-}" ]]; then
  expect_eq "FeeModule.pool == POOL" "$fee_pool" "$POOL"
else
  echo "⚠️  FeeModule check skipped: couldn't find pool()/sovereignPool() getter."
fi

if [[ -n "${FEE_SURPLUS:-}" && "${FEE_SURPLUS}" != "0x0000000000000000000000000000000000000000" ]]; then
  fs_pool=$(call_addr "$FEE_SURPLUS" "pool()(address)" 2>/dev/null || true)
  if [[ -n "${fs_pool:-}" ]]; then
    expect_eq "FeeSurplus.pool == POOL" "$fs_pool" "$POOL"
  else
    echo "⚠️  FEE_SURPLUS set but pool() not readable — skip."
  fi
fi

echo
echo "🎉 All critical wiring checks passed."
