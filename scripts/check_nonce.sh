#!/usr/bin/env bash
# Compare latest vs pending nonce for the deployer — helps debug -32003 "nonce too high"
# on the *first* broadcast tx (RPC nonce mismatch or stuck mempool).
#
# Usage:
#   ./scripts/check_nonce.sh 0xYourDeployer
#   RPC=https://other-rpc.example/evm ./scripts/check_nonce.sh 0xYourDeployer
set -euo pipefail
RPC="${RPC_URL:-${TESTNET_RPC_URL:-https://rpc.hyperliquid-testnet.xyz/evm}}"
ADDR="${1:?usage: $0 <deployer address>}"
L="$(cast nonce "$ADDR" --rpc-url "$RPC" --block latest)"
P="$(cast nonce "$ADDR" --rpc-url "$RPC" --block pending)"
echo "RPC: $RPC"
echo "address: $ADDR"
echo "nonce (latest / confirmed chain head): $L"
echo "nonce (pending — next nonce RPC will suggest for NEW txs): $P"
if [[ "$P" != "$L" ]]; then
  echo ""
  echo "latest != pending → you have txs in the mempool. Wait for them to land, or you may get"
  echo "'nonce too high' if submit path disagrees with the nonce used at simulation time."
fi
