# Backend API

The FastAPI app in **`backend/server.py`** listens for **`Swap`** logs on **`WATCH_POOL`**, broadcasts decoded events, and optionally runs **Hyperliquid spot** rebalance logic when **`ENABLE_HL_TRADING`** is true. Configure with **`backend/.env`** (see **`backend/.env.example`** if present).

## HTTP

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Config snapshot: watched pool, trading flag, spot market, rebalance band, chain, token addresses, HL account (if set). |
| `/events` | GET | Recent decoded swap events (`limit` query, capped). |
| `/hl/spot_state` | GET | Hyperliquid **spot user state** when trading is enabled; otherwise `trading_disabled`. |

## WebSocket

| Path | Description |
|------|-------------|
| `/ws` | Client connection for broadcast stream (swap + debug events emitted from the listener). |

## Environment flags

- **`ENABLE_HL_TRADING`** — When **true**, initializes Hyperliquid **`Exchange`** / **`Info`** and may place **spot** orders for ratio rebalance after swaps (requires **`HL_SECRET_KEY`**, **`HL_ACCOUNT_ADDRESS`**, etc.).

- **`ALCHEMY_WS_URL`**, **`EVM_RPC_HTTP_URL`**, **`STRATEGIST_EVM_PRIVATE_KEY`**, **`SOVEREIGN_VAULT`**, **`USDC_ADDRESS`**, **`PURR_ADDRESS`**, **`WATCH_POOL`** — Required for the listener and health checks.

Tune rebalance behavior with **`REBALANCE_BAND`**, **`MIN_HEDGE_USDC_MICRO`**, **`MAX_HEDGE_USDC_MICRO_PER_SWAP`**, **`HEDGE_COOLDOWN_MS`**, **`SPOT_MARKET`**.

See also [Current implementation — trading, fees, routing](../architecture/current-implementation.md) for how this relates to on-chain swaps.
