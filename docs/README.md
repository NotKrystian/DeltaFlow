# DeltaFlow

**Institutional-grade AMM on HyperEVM** — spot-index pricing, marginal-cost fees, risk management, and hedge orchestration backed by **Hyperliquid** spot and perps.

This documentation mirrors the protocol at a high level. For implementation detail, use the sidebar or the [GitHub repository](https://github.com/).

## What to read first

| If you want to… | Go to |
|-----------------|--------|
| Run the stack locally | [Quick start](getting-started/quick-start.md) |
| Understand the system | [Architecture](architecture/overview.md) |
| On-chain components | [Protocol contracts](protocol/contracts.md) |
| Backend & keeper | [Backend API](operations/backend-api.md) |

## At a glance

- **Chain:** Hyperliquid Testnet HyperEVM (chain ID `998`) for development.
- **Core:** `SovereignPool` + `SovereignALM` + `SovereignVault`, with DeltaFlow modules (quote engine, risk engine, state, circuit breaker, hedge executor, LP token).
- **Off-chain:** FastAPI backend for events, optional Hyperliquid spot trading and hedge reporting; Next.js frontend for swaps and liquidity.
