# Protocol contracts

Deploy scripts live under `contracts/script/` (e.g. **`DeployAll.s.sol`**, **`DeploySovereignVault.s.sol`**). Exact constructor wiring depends on your deployment — see the scripts and [Current implementation](../architecture/current-implementation.md) for what exists in **`contracts/src`**.

## Core (this repo)

- **SovereignPool** — Swaps and pool configuration; calls the swap fee module (if set), then the ALM, then settles tokens and fees.
- **SovereignALM** — **USDC/PURR** quotes from **`PrecompileLib.normalizedSpotPx`**; reverts if the vault cannot deliver **`tokenOut`** (+ buffer).
- **SovereignVault** — **ERC-20 LP** shares, `depositLP` / `withdrawLP`, **USDC** ↔ **HyperCore** via **`CoreWriterLib`**, **`sendTokensToRecipient`** for swap payouts.

## Swap fees

- **BalanceSeekingSwapFeeModuleV3** (`SwapFeeModuleV3.sol`) — Implements **`ISwapFeeModule`**: **base + imbalance** fee in bips, optional liquidity revert paths. Used when the pool’s swap fee module points to this contract.

If no fee module is configured, the pool uses its **default swap fee bips** (see `SovereignPool`).

## Source of truth

ABIs and bytecode: **`contracts/src/`** and Foundry **`out/`**. Runtime addresses: deployment records and **`NEXT_PUBLIC_*`** / backend `.env` variables.
