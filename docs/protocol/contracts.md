# Protocol contracts

Deploy scripts live under `contracts/script/`:

- **`AmmDeployBase.s.sol`** — Shared deploy logic for one USDC/base market (used by the scripts below).
- **`DeployAll.s.sol`** — **USDC/PURR** stack; optional **`DEPLOY_USDC_WETH`** adds a second **USDC/WETH** stack in the same broadcast. Env: **`SKIP_HL_AGENT`**, **`DEPLOY_HEDGE_ESCROW`**, **`RAW_PX_SCALE`**, pair-specific **`INVERT_*_PX`**. See [Pairs and deployment scripts](../deployment/pairs-and-scripts.md).
- **`DeployUsdcWeth.s.sol`** — Single **USDC/WETH** stack only (`WETH`, `SPOT_INDEX_WETH`, `INVERT_WETH_PX`, optional `RAW_PX_SCALE_WETH`).
- **`DeployHedgeEscrow.s.sol`** — Standalone **`HedgeEscrow`** with `spotAssetIndex = 10000 + spotIndex`.

Exact constructor wiring matches **`SovereignALM`** + **`BalanceSeekingSwapFeeModuleV3`** (`rawPxScale`, `rawIsPurrPerUsdc`); see [Current implementation](../architecture/current-implementation.md).

## Core (this repo)

- **SovereignPool** — Swaps and pool configuration; calls the swap fee module (if set), then the ALM, then settles tokens and fees.
- **SovereignALM** — **USDC/base** quotes from **`PrecompileLib.normalizedSpotPx`**; reverts if the vault cannot deliver **`tokenOut`** (+ buffer).
- **SovereignVault** — **ERC-20 LP** shares, `depositLP` / `withdrawLP`, **USDC** ↔ **HyperCore** via **`CoreWriterLib`**, **`sendTokensToRecipient`** for swap payouts.

## Swap fees

- **BalanceSeekingSwapFeeModuleV3** (`SwapFeeModuleV3.sol`) — Implements **`ISwapFeeModule`**: **base + imbalance** fee in bips; **base `decimals()`** and **`rawPxScale` / inversion** match **`SovereignALM`**.

If no fee module is configured, the pool uses its **default swap fee bips** (see `SovereignPool`).

## Hedge escrow

- **HedgeEscrow** — Optional; CoreWriter spot orders + claim path for a **base** token configured at deploy.

## Source of truth

ABIs and bytecode: **`contracts/src/`** and Foundry **`out/`**. Runtime addresses: deployment records and **`NEXT_PUBLIC_*`** / backend `.env` variables.
