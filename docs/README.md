# DeltaFlow

**Institutional-grade AMM on HyperEVM** — spot-index pricing, marginal-cost fees, risk management, and hedge orchestration backed by **Hyperliquid** spot and perps.

This documentation mirrors the protocol at a high level. For implementation detail, use the sidebar or the [GitHub repository](https://github.com/).

## What to read first

| If you want to… | Go to |
|-----------------|--------|
| **What the code does today** (fees, swaps, Core) | [Current implementation](architecture/current-implementation.md) |
| Run the stack locally | [Quick start](getting-started/quick-start.md) |
| Understand the system | [Architecture](architecture/overview.md) |
| On-chain components | [Protocol contracts](protocol/contracts.md) |
| Backend & API | [Backend API](operations/backend-api.md) |

## At a glance

- **Chain:** Hyperliquid Testnet HyperEVM (chain ID `998`) for development.
- **On-chain:** `SovereignPool` + `SovereignALM` (USDC/PURR spot index quotes) + `SovereignVault` (LP, USDC ↔ HyperCore via `CoreWriterLib`) + optional `SwapFeeModuleV3` balance-seeking fees.
- **Off-chain:** FastAPI backend for swap logs and optional Hyperliquid **spot** rebalance; Next.js for swaps and liquidity.

For the **accurate, code-level** description (fees, routing, what is *not* in the repo), start with [Current implementation](architecture/current-implementation.md).
