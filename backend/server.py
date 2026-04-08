"""
DeltaFlow backend: EVM swap log stream + HedgeEscrow status via Core precompiles.

Hedges execute **only** through on-chain CoreWriter (see `HedgeEscrow.sol`). This service
does **not** use Hyperliquid API wallets / `Exchange` for execution. It polls
`spotBalance` precompile (`0x…0801`) and `canClaimBuy` on the escrow contract so the UI
can show when users may claim.
"""

import os
import json
import time
import asyncio
import traceback
from typing import Any, Dict, List, Optional, Set

from dotenv import load_dotenv
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware

from web3 import Web3
import websockets

load_dotenv()

# -----------------------------
# ENV / CONFIG
# -----------------------------
ALCHEMY_WSS_URL = os.getenv("ALCHEMY_WSS_URL")
EVM_RPC_HTTP_URL = os.getenv("EVM_RPC_HTTP_URL")

SOVEREIGN_VAULT_ADDRESS = os.getenv("SOVEREIGN_VAULT")
USDC_ADDRESS = os.getenv("USDC_ADDRESS")
PURR_ADDRESS = os.getenv("PURR_ADDRESS")
WATCH_POOL = os.getenv("WATCH_POOL")

# Optional: deployed HedgeEscrow — enables /escrow/* and polling
HEDGE_ESCROW_ADDRESS = os.getenv("HEDGE_ESCROW")
# Core token index for PURR (not 0 — USDC is 0). Required for `/escrow/spot` PURR leg.
_PURR_TI = os.getenv("PURR_TOKEN_INDEX")
PURR_TOKEN_INDEX: Optional[int] = int(_PURR_TI) if _PURR_TI else None

DEBUG = os.getenv("DEBUG", "true").lower() == "true"
ESCROW_POLL_INTERVAL_S = float(os.getenv("ESCROW_POLL_INTERVAL_S", "4.0"))

MAX_EVENTS_STORED = int(os.getenv("MAX_EVENTS_STORED", "1000"))

SPOT_BALANCE_PRECOMPILE = Web3.to_checksum_address(
    "0x0000000000000000000000000000000000000801"
)

required = {
    "ALCHEMY_WS_URL": ALCHEMY_WSS_URL,
    "EVM_RPC_HTTP_URL": EVM_RPC_HTTP_URL,
    "SOVEREIGN_VAULT_ADDRESS": SOVEREIGN_VAULT_ADDRESS,
    "USDC_ADDRESS": USDC_ADDRESS,
    "PURR_ADDRESS": PURR_ADDRESS,
    "WATCH_POOL": WATCH_POOL,
}
missing = [k for k, v in required.items() if not v]
if missing:
    raise RuntimeError(f"Missing env vars: {missing}")

SOVEREIGN_VAULT_ADDRESS = Web3.to_checksum_address(SOVEREIGN_VAULT_ADDRESS)
USDC_ADDRESS = Web3.to_checksum_address(USDC_ADDRESS)
PURR_ADDRESS = Web3.to_checksum_address(PURR_ADDRESS)
WATCH_POOL = Web3.to_checksum_address(WATCH_POOL)
if HEDGE_ESCROW_ADDRESS:
    HEDGE_ESCROW_ADDRESS = Web3.to_checksum_address(HEDGE_ESCROW_ADDRESS)

# -----------------------------
# ABIs (minimal)
# -----------------------------
SOVEREIGN_VAULT_ABI = [
    {"type": "function", "name": "defaultVault", "stateMutability": "view", "inputs": [], "outputs": [{"name": "", "type": "address"}]},
]

HEDGE_ESCROW_ABI = [
    {
        "type": "function",
        "name": "nextTradeId",
        "stateMutability": "view",
        "inputs": [],
        "outputs": [{"name": "", "type": "uint256"}],
    },
    {
        "type": "function",
        "name": "canClaimBuy",
        "stateMutability": "view",
        "inputs": [{"name": "id", "type": "uint256"}],
        "outputs": [{"name": "", "type": "bool"}],
    },
    {
        "type": "function",
        "name": "trades",
        "stateMutability": "view",
        "inputs": [{"name": "", "type": "uint256"}],
        "outputs": [
            {"name": "user", "type": "address"},
            {"name": "isBuy", "type": "bool"},
            {"name": "limitPx", "type": "uint64"},
            {"name": "sz", "type": "uint64"},
            {"name": "cloid", "type": "uint128"},
            {"name": "purrSpotBefore", "type": "uint64"},
            {"name": "usdcSpotBefore", "type": "uint64"},
            {"name": "claimed", "type": "bool"},
        ],
    },
]

SWAP_TOPIC0 = Web3.to_hex(Web3.keccak(text="Swap(address,bool,uint256,uint256,uint256,int256)"))
assert SWAP_TOPIC0.startswith("0x") and len(SWAP_TOPIC0) == 66, f"bad topic0: {SWAP_TOPIC0}"

# -----------------------------
# Web3
# -----------------------------
w3_http = Web3(Web3.HTTPProvider(EVM_RPC_HTTP_URL))

vault_contract = w3_http.eth.contract(address=SOVEREIGN_VAULT_ADDRESS, abi=SOVEREIGN_VAULT_ABI)
hedge_escrow = (
    w3_http.eth.contract(address=HEDGE_ESCROW_ADDRESS, abi=HEDGE_ESCROW_ABI)
    if HEDGE_ESCROW_ADDRESS
    else None
)

CHAIN_ID = int(os.getenv("CHAIN_ID") or w3_http.eth.chain_id)

print("[boot] CHAIN_ID =", CHAIN_ID, flush=True)
print("[boot] HEDGE_ESCROW =", HEDGE_ESCROW_ADDRESS, "PURR_TOKEN_INDEX =", PURR_TOKEN_INDEX, flush=True)

# -----------------------------
# App state
# -----------------------------
state_lock = asyncio.Lock()
CLIENTS: Set[WebSocket] = set()
EVENTS: List[Dict[str, Any]] = []

# Latest escrow poll snapshot (id -> row)
escrow_claimable: Dict[int, Dict[str, Any]] = {}
escrow_poll_lock = asyncio.Lock()


def now_ms() -> int:
    return int(time.time() * 1000)


async def broadcast(msg: Dict[str, Any]) -> None:
    dead: List[WebSocket] = []
    payload = json.dumps(msg, default=str)
    for ws in list(CLIENTS):
        try:
            await ws.send_text(payload)
        except Exception:
            dead.append(ws)
    for ws in dead:
        CLIENTS.discard(ws)


async def debug_emit(event: str, data: Dict[str, Any]) -> None:
    if not DEBUG:
        return
    msg = {"type": "debug", "data": {"event": event, "ts_ms": now_ms(), **data}}
    print(f"[debug:{event}] {json.dumps(msg['data'], default=str)[:2000]}", flush=True)
    await broadcast(msg)


def decode_swap_log(log: dict) -> Dict[str, Any]:
    sender_topic = log["topics"][1]
    sender = Web3.to_checksum_address("0x" + sender_topic[-40:])

    data_bytes = Web3.to_bytes(hexstr=log["data"])
    isZeroToOne, amountIn, fee, amountOut, usdcDelta = w3_http.codec.decode(
        ["bool", "uint256", "uint256", "uint256", "int256"],
        data_bytes,
    )

    bn = log.get("blockNumber")
    block_number = int(bn, 16) if isinstance(bn, str) else int(bn)

    return {
        "pool": Web3.to_checksum_address(log["address"]),
        "sender": sender,
        "isZeroToOne": bool(isZeroToOne),
        "amountIn": int(amountIn),
        "fee": int(fee),
        "amountOut": int(amountOut),
        "usdcDelta": int(usdcDelta),
        "txHash": log.get("transactionHash"),
        "blockNumber": block_number,
    }


async def get_default_core_vault() -> str:
    v = await asyncio.to_thread(vault_contract.functions.defaultVault().call)
    return Web3.to_checksum_address(v)


def _call_spot_balance_precompile(user: str, token_index: int) -> Dict[str, int]:
    """spotBalance(address,uint64) -> (uint64 total, uint64 hold, uint64 entryNtl)"""
    data = w3_http.codec.encode(["address", "uint64"], [user, token_index])
    raw = w3_http.eth.call({"to": SPOT_BALANCE_PRECOMPILE, "data": data})
    total, hold, entry_ntl = w3_http.codec.decode(["uint64", "uint64", "uint64"], raw)
    return {"total": int(total), "hold": int(hold), "entryNtl": int(entry_ntl)}


async def poll_escrow_once() -> None:
    global escrow_claimable
    if not hedge_escrow or not HEDGE_ESCROW_ADDRESS:
        return

    def _read():
        nxt = hedge_escrow.functions.nextTradeId().call()
        out: Dict[int, Dict[str, Any]] = {}
        nxt = int(nxt)
        for tid in range(1, nxt):
            try:
                t = hedge_escrow.functions.trades(tid).call()
                user, is_buy, limit_px, sz, cloid, purr_bef, usdc_bef, claimed = t
                can_claim = False
                if not claimed and is_buy:
                    can_claim = hedge_escrow.functions.canClaimBuy(tid).call()
                out[tid] = {
                    "id": tid,
                    "user": user,
                    "isBuy": is_buy,
                    "limitPx": int(limit_px),
                    "sz": int(sz),
                    "cloid": str(cloid),
                    "purrSpotBefore": int(purr_bef),
                    "usdcSpotBefore": int(usdc_bef),
                    "claimed": bool(claimed),
                    "canClaimBuy": bool(can_claim),
                }
            except Exception as e:
                out[tid] = {"id": tid, "error": str(e)}
        return out

    snapshot = await asyncio.to_thread(_read)

    global escrow_claimable
    prev_claimable = {k for k, v in escrow_claimable.items() if v.get("canClaimBuy")}
    async with escrow_poll_lock:
        escrow_claimable = snapshot

    new_claimable = {k for k, v in snapshot.items() if v.get("canClaimBuy")}
    if new_claimable != prev_claimable:
        await broadcast(
            {
                "type": "escrow_claimable",
                "data": {
                    "claimableIds": sorted(new_claimable),
                    "trades": snapshot,
                },
            }
        )
        await debug_emit(
            "escrow_poll",
            {"claimableIds": sorted(new_claimable), "escrow": HEDGE_ESCROW_ADDRESS},
        )


async def escrow_poller_loop() -> None:
    while True:
        try:
            await poll_escrow_once()
        except Exception:
            await debug_emit("escrow_poll_crash", {"trace": traceback.format_exc()})
        await asyncio.sleep(ESCROW_POLL_INTERVAL_S)


async def evm_swap_listener_loop() -> None:
    while True:
        try:
            print("[evm_swap_listener] connecting...", flush=True)
            async with websockets.connect(ALCHEMY_WSS_URL, ping_interval=20, ping_timeout=20) as ws:
                params = {"address": WATCH_POOL, "topics": [SWAP_TOPIC0]}
                req = {"jsonrpc": "2.0", "id": 1, "method": "eth_subscribe", "params": ["logs", params]}

                await ws.send(json.dumps(req))
                resp_raw = await ws.recv()
                resp = json.loads(resp_raw)
                if "error" in resp:
                    raise RuntimeError(resp["error"])

                print(f"[evm_swap_listener] subscribed pool={WATCH_POOL}", flush=True)

                async for raw in ws:
                    try:
                        msg = json.loads(raw)
                    except Exception:
                        continue

                    if msg.get("method") != "eth_subscription":
                        continue

                    payload = msg.get("params", {}).get("result")
                    if not payload:
                        continue

                    try:
                        ev = decode_swap_log(payload)
                    except Exception:
                        await debug_emit("decode_swap_failed", {"trace": traceback.format_exc()})
                        continue

                    async with state_lock:
                        EVENTS.append(ev)
                        if len(EVENTS) > MAX_EVENTS_STORED:
                            del EVENTS[: len(EVENTS) - MAX_EVENTS_STORED]

                    await broadcast({"type": "swap", "data": ev})

        except asyncio.CancelledError:
            raise
        except Exception as e:
            print(f"[evm_swap_listener] error: {e} — reconnecting...", flush=True)
            await asyncio.sleep(2.0)


async def heartbeat_loop() -> None:
    while True:
        print(f"[heartbeat] clients={len(CLIENTS)} events={len(EVENTS)} escrow_trades={len(escrow_claimable)}", flush=True)
        await asyncio.sleep(10)


# -----------------------------
# Lifespan
# -----------------------------
from contextlib import asynccontextmanager

listener_task: Optional[asyncio.Task] = None
heartbeat_task: Optional[asyncio.Task] = None
escrow_task: Optional[asyncio.Task] = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global listener_task, heartbeat_task, escrow_task
    print("[lifespan] startup", flush=True)

    listener_task = asyncio.create_task(evm_swap_listener_loop(), name="evm_swap_listener")
    heartbeat_task = asyncio.create_task(heartbeat_loop(), name="heartbeat")

    if HEDGE_ESCROW_ADDRESS:
        escrow_task = asyncio.create_task(escrow_poller_loop(), name="escrow_poller")
        print("[lifespan] escrow poller started", flush=True)

    try:
        yield
    finally:
        for t in (listener_task, heartbeat_task, escrow_task):
            if t:
                t.cancel()
                try:
                    await t
                except asyncio.CancelledError:
                    pass
        print("[lifespan] shutdown complete", flush=True)


app = FastAPI(
    title="DeltaFlow — swap listener + CoreWriter escrow status",
    version="3.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("CORS_ORIGINS", "*").split(","),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
async def health() -> Dict[str, Any]:
    default_core_vault = await get_default_core_vault()
    return {
        "ok": True,
        "watchPool": WATCH_POOL,
        "swapTopic0": SWAP_TOPIC0,
        "defaultCoreVault": default_core_vault,
        "chainId": CHAIN_ID,
        "hedgeEscrow": HEDGE_ESCROW_ADDRESS,
        "purrTokenIndex": PURR_TOKEN_INDEX,
        "escrowPollIntervalS": ESCROW_POLL_INTERVAL_S,
    }


@app.get("/events")
async def get_events(limit: int = 200) -> List[Dict[str, Any]]:
    limit = max(1, min(limit, 2000))
    async with state_lock:
        evs = list(EVENTS)
    return evs[-limit:]


@app.get("/escrow/trades")
async def escrow_trades() -> Dict[str, Any]:
    """Snapshot of all hedge escrow trades + `canClaimBuy` (from contract view)."""
    if not HEDGE_ESCROW_ADDRESS:
        return {"ok": False, "reason": "HEDGE_ESCROW not configured"}
    async with escrow_poll_lock:
        snap = dict(escrow_claimable)
    return {
        "ok": True,
        "escrow": HEDGE_ESCROW_ADDRESS,
        "trades": snap,
    }


@app.get("/escrow/spot/{user}")
async def escrow_spot_snapshot(user: str) -> Dict[str, Any]:
    """Raw precompile spot balances for an address (USDC index 0 + PURR index from env)."""
    user = Web3.to_checksum_address(user)

    def _read():
        usdc_b = _call_spot_balance_precompile(user, 0)
        if PURR_TOKEN_INDEX is None:
            return usdc_b, None
        purr_b = _call_spot_balance_precompile(user, PURR_TOKEN_INDEX)
        return usdc_b, purr_b

    usdc_b, purr_b = await asyncio.to_thread(_read)
    out: Dict[str, Any] = {
        "ok": True,
        "user": user,
        "usdcToken0": usdc_b,
        "purrTokenIndex": PURR_TOKEN_INDEX,
    }
    if purr_b is not None:
        out["purrToken"] = purr_b
    return out


@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket):
    await ws.accept()
    CLIENTS.add(ws)
    try:
        await ws.send_text(
            json.dumps(
                {
                    "type": "hello",
                    "data": {"watchPool": WATCH_POOL, "hedgeEscrow": HEDGE_ESCROW_ADDRESS, "debug": DEBUG},
                }
            )
        )
        while True:
            _ = await ws.receive_text()
    except WebSocketDisconnect:
        pass
    finally:
        CLIENTS.discard(ws)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", "8000")), log_level="debug")
