# System overview

{% hint style="success" %}
**Authoritative detail for the current repo:** [Current implementation — trading, fees, routing](current-implementation.md) (USDC/PURR, balance-seeking fees, vault ↔ Core).
{% endhint %}

DeltaFlow is designed around **spot-index pricing**, **vault-held liquidity**, and **HyperCore** connectivity on **HyperEVM**. The exact modules deployed vary by branch; the page linked above matches **`contracts/src`** in this repository.

## On-chain (HyperEVM) — present in this repo

| Layer | Role |
|--------|------|
| **SovereignPool** | Valantis-style pool: swap routing, swap fee module, ALM quote, vault token flows. |
| **SovereignALM** | Quotes **USDC/PURR** from the Hyperliquid **spot index** (`PrecompileLib`); enforces vault liquidity for `tokenOut`. |
| **BalanceSeekingSwapFeeModuleV3** | Optional `ISwapFeeModule`: **base fee + imbalance** vs spot-valued inventory, clamped to min/max bips. |
| **SovereignVault** | LP token (`DFLP`), deposits/withdrawals, **USDC** bridge/allocate/deallocate via **CoreWriter**, `sendTokensToRecipient` for swaps. |

## HyperCore

Oracle, mark, BBO, spot balance, and **CoreWriter** precompiles sit under Hyperliquid’s stack; the repo README lists useful testnet addresses.

## Off-chain

| Component | Role |
|-----------|------|
| **Backend (FastAPI)** | Swap log subscription, REST + `/ws`, optional **Hyperliquid spot** rebalance when enabled. |
| **Frontend (Next.js)** | Wallet on chain `998`, swap and liquidity UI. |

## Roadmap / extended design

A fuller design can add separate **risk**, **multi-component quote**, **circuit breaker**, **on-chain hedge FSM**, and dedicated **LP token** contracts. Those are **not** described as deployed here — see the [current implementation](current-implementation.md) page for scope.
