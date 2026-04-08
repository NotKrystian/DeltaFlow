# Backend API

The FastAPI server (`backend/server.py`) exposes monitoring and optional keeper flows. Configure via `backend/.env` (see `backend/.env.example`).

## HTTP

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health and config snapshot |
| `/events` | GET | Recent swap events (`limit` query) |
| `/pool/state` | GET | On-chain `DeltaFlowState` + vault balances (when addresses set) |
| `/pool/stats` | GET | Aggregated stats + circuit breaker level |
| `/hedge/status` | GET | Pending hedges from `HedgeExecutor` |
| `/hl/spot_state` | GET | Hyperliquid spot balances (when HL trading enabled) |

## WebSocket

| Path | Description |
|------|-------------|
| `/ws` | Live swap-related events and optional debug stream |

## Flags

- **`ENABLE_HL_TRADING`** — Use Hyperliquid API for spot rebalance / hedging (requires HL keys in env).
- **`ENABLE_KEEPER`** — Submit on-chain hedge updates via strategist key.

Full variable list: **`backend/.env.example`** in the repository.
