# Backend API

The FastAPI app in **`backend/server.py`** streams **`Swap`** logs from **`WATCH_POOL`** and polls **`HedgeEscrow`** + Core precompiles so the UI can show **claimable** hedges. **`HEDGE_ESCROW`** and **`PURR_TOKEN_INDEX`** are **required**. **Hyperliquid API wallets / `Exchange` are not used** for hedge execution — orders are placed on-chain via **CoreWriter** inside **`HedgeEscrow.sol`**.

```mermaid
flowchart LR
  RPC[EVM RPC + Alchemy WSS]
  S[server.py]
  P[(WATCH_POOL)]
  E[HedgeEscrow]
  RPC --> S
  S --> P
  S --> E
```

## HTTP

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Pool, chain, **`hedgeEscrow`**, **`purrTokenIndex`**, poll interval. |
| `/events` | GET | Recent decoded swap events (`limit`). |
| `/escrow/trades` | GET | Snapshot of all escrow trades + **`canClaimBuy`**. |
| `/escrow/spot/{user}` | GET | Raw **`spotBalance`** precompile reads for USDC (`token 0`) and base token (**`PURR_TOKEN_INDEX`** — Core token index for the pool base asset; name is legacy). |

## WebSocket

| Path | Description |
|------|-------------|
| `/ws` | Swap events + **`escrow_claimable`** when claimability changes. |

## Environment

See **`backend/.env.example`**. Important:

- **`HEDGE_ESCROW`** — Deployed **`HedgeEscrow`** address.
- **`PURR_TOKEN_INDEX`** — HyperCore **token index** for the **base** asset (PURR, WETH, etc.), not the perp universe id.

Tune **`ESCROW_POLL_INTERVAL_S`** (default **4**).

## Frontend

Set **`NEXT_PUBLIC_HEDGE_ESCROW`** and **`NEXT_PUBLIC_BACKEND_URL`** (e.g. `http://127.0.0.1:8000`) for the **Hedge** tab.
