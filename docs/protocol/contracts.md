# Protocol contracts

Deployment order for the full stack is scripted in `contracts/script/DeployDeltaFlow.s.sol` (vault → pool → state → circuit breaker → quote/risk engines → ALM → hedge executor → LP token → wiring).

## Core

- **SovereignPool** — Pool entrypoint for swaps and liquidity; coordinates ALM and fee module.
- **SovereignALM** — WETH/USDC quoting using the configured spot index; checks vault liquidity; routes through risk, circuit breaker, state, and hedge executor when configured.
- **SovereignVault** — Holds assets and integrates with vault/agent patterns used on Hyperliquid.

## DeltaFlow modules

- **DeltaFlowQuoteEngine** — Fee components (execution, impact, delay, basis, funding, inventory skew, exhaustion, safety tiers).
- **DeltaFlowRiskEngine** — Exposure, venue, fee cap, shortfall, hedge feasibility, stress rules.
- **CircuitBreaker** — Degradation levels affecting fees, size caps, and allowed trade directions.
- **DeltaFlowState** — Authoritative on-chain accounting surface for strategy and analytics.
- **HedgeExecutor** — State machine for hedge trades tied to swaps.
- **DeltaFlowLPToken** — ERC-20 LP representation linked to vault/state.

## Legacy / auxiliary

- **SwapFeeModuleV3** — Balance-seeking fee module where used as fallback.

Source of truth for ABIs and addresses: `contracts/src/` and your deployment `.env` / frontend `NEXT_PUBLIC_*` variables.
