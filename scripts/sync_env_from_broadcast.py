#!/usr/bin/env python3
"""
Merge addresses from Foundry broadcast artifacts into frontend/.env.local and backend/.env.

Run automatically after: forge script ... DeployAll ... --broadcast

Usage:
  python3 scripts/sync_env_from_broadcast.py
  python3 scripts/sync_env_from_broadcast.py --dry-run
  CHAIN_ID=998 python3 scripts/sync_env_from_broadcast.py --rpc-url https://rpc.hyperliquid-testnet.xyz/evm
  # After two-phase deploy (stack1 + stack2), merge broadcast JSONs:
  #   python3 scripts/sync_env_from_broadcast.py --broadcast-json run-after-stack1.json --broadcast-json run-latest.json
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Optional

ROOT = Path(__file__).resolve().parents[1]
ADDR_RE = re.compile(r"0x[a-fA-F0-9]{40}")


def _norm_addr(a: str) -> str:
    return "0x" + a.lower().removeprefix("0x")


def _parse_stacks(transactions: list[dict]) -> list[dict]:
    """Split CREATE txs into stacks at each SovereignVault deployment."""
    stacks: list[dict[str, Any]] = []
    cur: Optional[dict[str, Any]] = None

    for tx in transactions:
        if tx.get("transactionType") != "CREATE":
            continue
        name = tx.get("contractName") or ""
        raw = tx.get("contractAddress") or ""
        if not raw:
            continue
        addr = _norm_addr(raw)

        if name == "SovereignVault":
            if cur:
                stacks.append(cur)
            cur = {"vault": addr}
            continue
        if cur is None:
            continue

        if name == "SovereignPool":
            cur["pool"] = addr
            args = tx.get("arguments") or []
            if args:
                m = ADDR_RE.findall(str(args[0]))
                if len(m) >= 2:
                    cur["token0"] = _norm_addr(m[0])
                    cur["token1"] = _norm_addr(m[1])
        elif name == "SovereignALM":
            cur["alm"] = addr
        elif name == "FeeSurplus":
            cur["fee_surplus"] = addr
        elif name == "DeltaFlowRiskEngine":
            cur["risk_engine"] = addr
        elif name == "DeltaFlowCompositeFeeModule":
            cur["fee_module"] = addr
        elif name == "BalanceSeekingSwapFeeModuleV3":
            cur["fee_module"] = addr
        elif name == "HedgeEscrow":
            cur["hedge_escrow"] = addr
            args = tx.get("arguments") or []
            if len(args) >= 4:
                ti_raw = args[3]
                try:
                    if isinstance(ti_raw, str) and ti_raw.startswith("0x"):
                        cur["purr_token_index"] = str(int(ti_raw, 16))
                    else:
                        cur["purr_token_index"] = str(int(str(ti_raw), 10))
                except (TypeError, ValueError):
                    pass

    if cur:
        stacks.append(cur)
    return stacks


def _hedge_purr_token_index(hedge: str, rpc: str | None) -> str | None:
    if not rpc:
        return None
    try:
        out = subprocess.check_output(
            ["cast", "call", hedge, "purrTokenIndex()(uint64)", "--rpc-url", rpc],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=30,
        ).strip()
        if out.startswith("0x"):
            return str(int(out, 16))
        return out or None
    except (subprocess.CalledProcessError, FileNotFoundError, ValueError, subprocess.TimeoutExpired):
        return None


def _merge_env(path: Path, updates: dict[str, str], dry_run: bool) -> None:
    lines: list[str] = []
    if path.exists():
        lines = path.read_text().splitlines()

    present: set[str] = set()
    out: list[str] = []
    for line in lines:
        s = line.strip()
        if s and not s.startswith("#") and "=" in line:
            k = line.split("=", 1)[0].strip()
            if k in updates:
                out.append(f"{k}={updates[k]}")
                present.add(k)
                continue
        out.append(line)

    for k, v in updates.items():
        if k not in present:
            out.append(f"{k}={v}")

    text = "\n".join(out).rstrip() + "\n"
    if dry_run:
        print(f"--- would write {path} ---")
        print(text)
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    print(f"Wrote {path}")


def main() -> int:
    ap = argparse.ArgumentParser(description="Sync deploy addresses into env files from Foundry broadcast JSON.")
    ap.add_argument(
        "--broadcast-json",
        type=Path,
        action="append",
        dest="broadcast_jsons",
        default=None,
        help="Path to broadcast JSON (repeat for merge: stack1 run + stack2 run). Default: single run-latest.json",
    )
    ap.add_argument("--chain-id", type=int, default=int(os.environ.get("CHAIN_ID", "998")))
    ap.add_argument("--rpc-url", default=os.environ.get("RPC_URL", os.environ.get("TESTNET_RPC_URL")))
    ap.add_argument("--frontend-env", type=Path, default=ROOT / "frontend" / ".env.local")
    ap.add_argument("--backend-env", type=Path, default=ROOT / "backend" / ".env")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    bj_list = args.broadcast_jsons
    if not bj_list:
        bj_list = [ROOT / "broadcast" / "DeployAll.s.sol" / str(args.chain_id) / "run-latest.json"]

    for bj in bj_list:
        if not bj.is_file():
            print(f"Error: broadcast file not found: {bj}", file=sys.stderr)
            print("Deploy first with: forge script contracts/script/DeployAll.s.sol:DeployAll --broadcast", file=sys.stderr)
            return 1

    merged_txs: list[dict[str, Any]] = []
    for bj in bj_list:
        data = json.loads(bj.read_text())
        merged_txs.extend(data.get("transactions") or [])
    txs = merged_txs
    stacks = _parse_stacks(txs)
    if not stacks:
        print("Error: no SovereignVault deployments found in broadcast (empty or wrong script?)", file=sys.stderr)
        return 1

    primary = stacks[0]
    fe: dict[str, str] = {}
    be: dict[str, str] = {}

    # Primary stack (USDC/PURR or first market)
    fe["NEXT_PUBLIC_POOL"] = primary["pool"]
    fe["NEXT_PUBLIC_VAULT"] = primary["vault"]
    fe["NEXT_PUBLIC_ALM"] = primary["alm"]
    fe["NEXT_PUBLIC_SWAP_FEE_MODULE"] = primary.get("fee_module", "0x0000000000000000000000000000000000000000")
    fe["NEXT_PUBLIC_FEE_SURPLUS"] = primary.get("fee_surplus", "0x0000000000000000000000000000000000000000")
    fe["NEXT_PUBLIC_DELTAFLOW_RISK_ENGINE"] = primary.get("risk_engine", "0x0000000000000000000000000000000000000000")

    if "token1" in primary:
        fe["NEXT_PUBLIC_USDC"] = primary["token1"]
        be["USDC_ADDRESS"] = primary["token1"]
    if "token0" in primary:
        fe["NEXT_PUBLIC_PURR"] = primary["token0"]
        be["PURR_ADDRESS"] = primary["token0"]

    be["SOVEREIGN_VAULT"] = primary["vault"]
    be["WATCH_POOL"] = primary["pool"]
    be["CHAIN_ID"] = str(args.chain_id)

    he = primary.get("hedge_escrow")
    if not he:
        print(
            "Error: no HedgeEscrow in broadcast (DeployAll always deploys it). Use a fresh DeployAll broadcast.",
            file=sys.stderr,
        )
        return 1

    fe["NEXT_PUBLIC_HEDGE_ESCROW"] = he
    be["HEDGE_ESCROW"] = he
    pti = _hedge_purr_token_index(he, args.rpc_url)
    if pti is None:
        pti = primary.get("purr_token_index")
    if pti is not None:
        be["PURR_TOKEN_INDEX"] = pti

    # Second stack (USDC/WETH)
    if len(stacks) > 1:
        w = stacks[1]
        fe["NEXT_PUBLIC_POOL_WETH"] = w["pool"]
        fe["NEXT_PUBLIC_VAULT_WETH"] = w["vault"]
        fe["NEXT_PUBLIC_ALM_WETH"] = w["alm"]
        fe["NEXT_PUBLIC_SWAP_FEE_MODULE_WETH"] = w.get("fee_module", "0x0000000000000000000000000000000000000000")
        fe["NEXT_PUBLIC_FEE_SURPLUS_WETH"] = w.get("fee_surplus", "0x0000000000000000000000000000000000000000")
        fe["NEXT_PUBLIC_DELTAFLOW_RISK_ENGINE_WETH"] = w.get("risk_engine", "0x0000000000000000000000000000000000000000")
        if "token0" in w:
            fe["NEXT_PUBLIC_WETH"] = w["token0"]
        he_w = w.get("hedge_escrow")
        if he_w:
            fe["NEXT_PUBLIC_HEDGE_ESCROW_WETH"] = he_w

    if not args.dry_run:
        if len(bj_list) == 1:
            print(f"Using broadcast: {bj_list[0]}")
        else:
            print("Using merged broadcasts:")
            for p in bj_list:
                print(f"  {p}")
        print(f"Stacks parsed: {len(stacks)}")

    _merge_env(args.frontend_env, fe, args.dry_run)
    _merge_env(args.backend_env, be, args.dry_run)

    if "PURR_TOKEN_INDEX" not in be and not args.dry_run:
        print(
            "Error: PURR_TOKEN_INDEX missing (need HedgeEscrow constructor args in broadcast, or run with RPC_URL + `cast`).",
            file=sys.stderr,
        )
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
