"""
DeltaFlow backend: EVM swap log polling + HedgeEscrow status via Core precompiles.

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

load_dotenv()

# -----------------------------
# ENV / CONFIG
# -----------------------------
EVM_RPC_HTTP_URL = os.getenv("EVM_RPC_HTTP_URL")

SOVEREIGN_VAULT_ADDRESS = os.getenv("SOVEREIGN_VAULT")
USDC_ADDRESS = os.getenv("USDC_ADDRESS")
PURR_ADDRESS = os.getenv("PURR_ADDRESS")
WATCH_POOL = os.getenv("WATCH_POOL")

HEDGE_ESCROW_ADDRESS = os.getenv("HEDGE_ESCROW")
_PURR_TI = os.getenv("PURR_TOKEN_INDEX")

DEBUG = os.getenv("DEBUG", "true").lower() == "true"
ESCROW_POLL_INTERVAL_S = float(os.getenv("ESCROW_POLL_INTERVAL_S", "4.0"))
SWAP_POLL_INTERVAL_S = float(os.getenv("SWAP_POLL_INTERVAL_S", "30.0"))
# Optional backfill on first poll only (blocks behind head); 0 = start from current head only
SWAP_LOG_LOOKBACK_BLOCKS = int(os.getenv("SWAP_LOG_LOOKBACK_BLOCKS", "0"))
MAX_GET_LOGS_BLOCK_RANGE = int(os.getenv("MAX_GET_LOGS_BLOCK_RANGE", "2000"))

MAX_EVENTS_STORED = int(os.getenv("MAX_EVENTS_STORED", "1000"))

SPOT_BALANCE_PRECOMPILE = Web3.to_checksum_address(
    "0x0000000000000000000000000000000000000801"
)

required = {
    "EVM_RPC_HTTP_URL": EVM_RPC_HTTP_URL,
    "SOVEREIGN_VAULT_ADDRESS": SOVEREIGN_VAULT_ADDRESS,
    "USDC_ADDRESS": USDC_ADDRESS,
    "PURR_ADDRESS": PURR_ADDRESS,
    "WATCH_POOL": WATCH_POOL,
    "HEDGE_ESCROW": HEDGE_ESCROW_ADDRESS,
    "PURR_TOKEN_INDEX": _PURR_TI,
}
missing = [k for k, v in required.items() if not v]
if missing:
    raise RuntimeError(f"Missing env vars: {missing}")

_ZERO = "0x0000000000000000000000000000000000000000"
if HEDGE_ESCROW_ADDRESS and HEDGE_ESCROW_ADDRESS.lower() == _ZERO:
    raise RuntimeError("HEDGE_ESCROW must be a deployed HedgeEscrow address (not zero)")

SOVEREIGN_VAULT_ADDRESS = Web3.to_checksum_address(SOVEREIGN_VAULT_ADDRESS)
USDC_ADDRESS = Web3.to_checksum_address(USDC_ADDRESS)
PURR_ADDRESS = Web3.to_checksum_address(PURR_ADDRESS)
WATCH_POOL = Web3.to_checksum_address(WATCH_POOL)
HEDGE_ESCROW_ADDRESS = Web3.to_checksum_address(HEDGE_ESCROW_ADDRESS)

try:
    PURR_TOKEN_INDEX: int = int(_PURR_TI or "", 10)
except ValueError as e:
    raise RuntimeError("PURR_TOKEN_INDEX must be a decimal integer (Core token index for the pool base asset)") from e
if PURR_TOKEN_INDEX < 0:
    raise RuntimeError("PURR_TOKEN_INDEX invalid")

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
hedge_escrow = w3_http.eth.contract(address=HEDGE_ESCROW_ADDRESS, abi=HEDGE_ESCROW_ABI)

CHAIN_ID = int(os.getenv("CHAIN_ID") or w3_http.eth.chain_id)

print("[boot] CHAIN_ID =", CHAIN_ID, flush=True)
print("[boot] HEDGE_ESCROW =", HEDGE_ESCROW_ADDRESS, "PURR_TOKEN_INDEX =", PURR_TOKEN_INDEX, flush=True)
print(
    "[boot] swap poll: interval_s=",
    SWAP_POLL_INTERVAL_S,
    "lookback_blocks=",
    SWAP_LOG_LOOKBACK_BLOCKS,
    flush=True,
)

# -----------------------------
# App state
# -----------------------------
state_lock = asyncio.Lock()
CLIENTS: Set[WebSocket] = set()
EVENTS: List[Dict[str, Any]] = []
# Last chain block fully scanned for Swap logs (HTTP polling); None until first poll initializes
last_swap_block_processed: Optional[int] = None

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


def _topic1_to_address(topic: Any) -> str:
    """Decode indexed address from Swap event topic (handles str / HexBytes)."""
    if isinstance(topic, (bytes, bytearray)):
        return Web3.to_checksum_address(bytes(topic)[-20:])
    if isinstance(topic, str):
        h = topic[2:] if topic.startswith("0x") else topic
        return Web3.to_checksum_address("0x" + h[-40:])
    hx = topic.hex()
    if hx.startswith("0x"):
        hx = hx[2:]
    return Web3.to_checksum_address("0x" + hx[-40:])


def decode_swap_log(log: dict) -> Dict[str, Any]:
    sender = _topic1_to_address(log["topics"][1])

    raw_data = log["data"]
    if isinstance(raw_data, (bytes, bytearray)):
        data_bytes = bytes(raw_data)
    else:
        data_bytes = Web3.to_bytes(hexstr=raw_data)
    isZeroToOne, amountIn, fee, amountOut, usdcDelta = w3_http.codec.decode(
        ["bool", "uint256", "uint256", "uint256", "int256"],
        data_bytes,
    )

    bn = log.get("blockNumber")
    if bn is None:
        block_number = 0
    else:
        block_number = int(bn, 16) if isinstance(bn, str) else int(bn)

    addr = log["address"]
    pool_addr = Web3.to_checksum_address(addr)

    th = log.get("transactionHash")
    tx_hex = Web3.to_hex(th) if th is not None else None

    return {
        "pool": pool_addr,
        "sender": sender,
        "isZeroToOne": bool(isZeroToOne),
        "amountIn": int(amountIn),
        "fee": int(fee),
        "amountOut": int(amountOut),
        "usdcDelta": int(usdcDelta),
        "txHash": tx_hex,
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


def _log_sort_key(log: Any) -> tuple:
    bn = log["blockNumber"]
    bi = int(bn, 16) if isinstance(bn, str) else int(bn)
    li = log.get("logIndex", 0)
    li = int(li, 16) if isinstance(li, str) else int(li)
    return (bi, li)


def _get_logs_chunked(from_block: int, to_block: int) -> List[Any]:
    """eth_getLogs in chunks (RPCs often cap block range)."""
    out: List[Any] = []
    fb = from_block
    rng = max(1, MAX_GET_LOGS_BLOCK_RANGE)
    while fb <= to_block:
        tb = min(fb + rng - 1, to_block)
        chunk = w3_http.eth.get_logs(
            {
                "fromBlock": fb,
                "toBlock": tb,
                "address": WATCH_POOL,
                "topics": [SWAP_TOPIC0],
            }
        )
        out.extend(chunk)
        fb = tb + 1
    return out


def _sync_fetch_new_swaps(last_processed: Optional[int]) -> tuple[List[Dict[str, Any]], int]:
    """
    Returns decoded Swap events and the new high-water block number (inclusive).
    If last_processed is None, scans from max(0, latest - SWAP_LOG_LOOKBACK_BLOCKS).
    """
    latest = int(w3_http.eth.block_number)
    if last_processed is None:
        from_block = max(0, latest - max(0, SWAP_LOG_LOOKBACK_BLOCKS))
    else:
        from_block = last_processed + 1
    to_block = latest
    if from_block > to_block:
        return [], last_processed if last_processed is not None else latest

    raw_logs = _get_logs_chunked(from_block, to_block)
    raw_logs = sorted(raw_logs, key=_log_sort_key)
    events: List[Dict[str, Any]] = []
    for raw in raw_logs:
        try:
            events.append(decode_swap_log(dict(raw)))
        except Exception:
            print("[evm_swap_poll] decode_swap_log failed", flush=True)
            traceback.print_exc()
    return events, to_block


async def evm_swap_poll_loop() -> None:
    global last_swap_block_processed
    while True:
        try:
            events, new_high = await asyncio.to_thread(_sync_fetch_new_swaps, last_swap_block_processed)
            if last_swap_block_processed is None:
                print(
                    f"[evm_swap_poll] initialized through block {new_high} "
                    f"(lookback_blocks={SWAP_LOG_LOOKBACK_BLOCKS})",
                    flush=True,
                )
            elif events:
                print(
                    f"[evm_swap_poll] +{len(events)} swap(s) blocks "
                    f"{last_swap_block_processed + 1}-{new_high}",
                    flush=True,
                )
            async with state_lock:
                last_swap_block_processed = new_high
                for ev in events:
                    EVENTS.append(ev)
                    if len(EVENTS) > MAX_EVENTS_STORED:
                        del EVENTS[: len(EVENTS) - MAX_EVENTS_STORED]
            for ev in events:
                await broadcast({"type": "swap", "data": ev})
        except asyncio.CancelledError:
            raise
        except Exception as e:
            print(f"[evm_swap_poll] error: {e} — retrying...", flush=True)
            traceback.print_exc()
            await debug_emit("swap_poll_crash", {"trace": traceback.format_exc()})
        await asyncio.sleep(SWAP_POLL_INTERVAL_S)


async def heartbeat_loop() -> None:
    while True:
        print(
            f"[heartbeat] clients={len(CLIENTS)} events={len(EVENTS)} "
            f"last_swap_block={last_swap_block_processed} escrow_trades={len(escrow_claimable)}",
            flush=True,
        )
        await asyncio.sleep(10)


# -----------------------------
# Lifespan
# -----------------------------
from contextlib import asynccontextmanager

swap_poll_task: Optional[asyncio.Task] = None
heartbeat_task: Optional[asyncio.Task] = None
escrow_task: Optional[asyncio.Task] = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global swap_poll_task, heartbeat_task, escrow_task
    print("[lifespan] startup", flush=True)

    swap_poll_task = asyncio.create_task(evm_swap_poll_loop(), name="evm_swap_poll")
    heartbeat_task = asyncio.create_task(heartbeat_loop(), name="heartbeat")

    escrow_task = asyncio.create_task(escrow_poller_loop(), name="escrow_poller")
    print("[lifespan] escrow poller started", flush=True)

    try:
        yield
    finally:
        for t in (swap_poll_task, heartbeat_task, escrow_task):
            if t:
                t.cancel()
                try:
                    await t
                except asyncio.CancelledError:
                    pass
        print("[lifespan] shutdown complete", flush=True)


app = FastAPI(
    title="DeltaFlow — swap log polling + CoreWriter escrow status",
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
    async with state_lock:
        swap_head = last_swap_block_processed
    return {
        "ok": True,
        "watchPool": WATCH_POOL,
        "swapTopic0": SWAP_TOPIC0,
        "defaultCoreVault": default_core_vault,
        "chainId": CHAIN_ID,
        "hedgeEscrow": HEDGE_ESCROW_ADDRESS,
        "purrTokenIndex": PURR_TOKEN_INDEX,
        "escrowPollIntervalS": ESCROW_POLL_INTERVAL_S,
        "swapPollIntervalS": SWAP_POLL_INTERVAL_S,
        "swapLogLookbackBlocks": SWAP_LOG_LOOKBACK_BLOCKS,
        "lastSwapBlockProcessed": swap_head,
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
        purr_b = _call_spot_balance_precompile(user, PURR_TOKEN_INDEX)
        return usdc_b, purr_b

    usdc_b, purr_b = await asyncio.to_thread(_read)
    return {
        "ok": True,
        "user": user,
        "usdcToken0": usdc_b,
        "purrTokenIndex": PURR_TOKEN_INDEX,
        "purrToken": purr_b,
    }


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
