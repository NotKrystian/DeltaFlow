# System overview

DeltaFlow separates **pricing**, **risk**, **inventory accounting**, and **hedge lifecycle** while keeping swaps on **HyperEVM** and connecting to **HyperCore** precompiles and bridges where needed.

## On-chain (HyperEVM)

| Layer | Role |
|--------|------|
| **SovereignPool** | Valantis-style pool: swap routing, ALM quote consumption, optional vault-held reserves. |
| **SovereignALM** | Liquidity quotes from Hyperliquid **spot index** (precompiles via `PrecompileLib`); integrates DeltaFlow modules. |
| **DeltaFlowQuoteEngine** | Multi-component fee model (`ISwapFeeModule`). |
| **DeltaFlowRiskEngine** | Trade acceptance / rejection vs inventory and market stress. |
| **CircuitBreaker** | Graduated limits (L0–L5). |
| **DeltaFlowState** | Inventory, NAV, fee and hedge cost aggregates. |
| **HedgeExecutor** | On-chain FSM for hedge submission, fills, settlement, timeouts. |
| **DeltaFlowLPToken** | LP shares with withdrawal cooldown semantics. |
| **SovereignVault** | Token custody and HyperCore-related flows. |

## HyperCore

Oracle, mark, BBO, spot balance, and **CoreWriter** precompiles sit under Hyperliquid’s L1; the README in the repo lists testnet addresses (e.g. Oracle `0x…807`, CoreWriter `0x…3333`).

## Off-chain

| Component | Role |
|-----------|------|
| **Backend (FastAPI)** | WebSocket log subscription (e.g. swaps), REST + `/ws`, optional Hyperliquid spot orders and keeper txs to `HedgeExecutor`. |
| **Frontend (Next.js)** | Wallet connect to chain `998`, swap / add / remove liquidity, dashboard and strategist tooling. |

For sequence diagrams and fee/risk enumerations, see the main repository **README.md** (architecture and lifecycle sections).
