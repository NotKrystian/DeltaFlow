# DeltaFlow

**AMM on HyperEVM** — spot-index pricing, balance-seeking fees, vault-held liquidity, optional **HedgeEscrow** hedges via **CoreWriter** (no API-wallet execution in the current backend).

This documentation matches **`contracts/src`** and the backend in this repository. For the full detail, start with [Current implementation](architecture/current-implementation.md).

## What to read first

| If you want to… | Go to |
|-----------------|--------|
| **What the code does today** (fees, swaps, Core, escrow) | [Current implementation](architecture/current-implementation.md) |
| Deploy **USDC/PURR** vs **USDC/WETH** | [Pairs and deployment scripts](deployment/pairs-and-scripts.md) |
| Run the stack locally | [Quick start](getting-started/quick-start.md) |
| System overview | [Architecture](architecture/overview.md) |
| On-chain components | [Protocol contracts](protocol/contracts.md) |
| Backend & API | [Backend API](operations/backend-api.md) |

## At a glance

- **Chain:** Hyperliquid Testnet HyperEVM (chain ID `998`) for development.
- **On-chain:** `SovereignPool` + `SovereignALM` + `SovereignVault` + optional `BalanceSeekingSwapFeeModuleV3` + optional `HedgeEscrow`.
- **Pairs:** Primary docs describe **USDC/PURR**; **USDC/WETH** uses the same contracts in a **separate** deploy (vault + pool + ALM + fee module per pair). See [Pairs and deployment scripts](deployment/pairs-and-scripts.md).
- **Off-chain:** FastAPI backend for swap logs and **`/escrow/trades`** when configured; Next.js for swap, liquidity, and Hedge UI.

For the **accurate, code-level** description, use [Current implementation](architecture/current-implementation.md).
