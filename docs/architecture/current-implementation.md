# Current implementation (trading, fees, routing)

This page describes **what the repository code does today**: **USDC / PURR** on HyperEVM, **balance-seeking** swap fees, and **vault ↔ HyperCore** USDC flows. It is the ground truth for `contracts/src` as maintained in Git.

{% hint style="info" %}
Older marketing materials or README sections may still mention WETH, an eight-component quote engine, risk engine, or hedge FSM. Those modules are **not** present in the current Solidity tree unless explicitly reintroduced. When in doubt, trust this page and the contracts.
{% endhint %}

---

## Trading (user-facing)

1. **Execution path** — Users trade **on-chain** by calling **`SovereignPool.swap()`**. The frontend submits this via wallet (`useSwap` → pool address + ABI).

2. **Pair** — **USDC** and **PURR** (the UI uses **6** decimals for USDC and **5** for PURR).

3. **Pricing** — Output amounts are **not** from constant-product reserves. **`SovereignALM`**:
   - Reads **`PrecompileLib.normalizedSpotPx(spotIndexPURR)`** and derives **USDC per 1 PURR** (`getSpotPriceUSDCperPURR`).
   - Computes **`amountOut`** from **`amountInMinusFee`** using spot math only.
   - **Reverts** if the **sovereign vault** cannot cover **`tokenOut`** plus a configured **liquidity buffer** (bps).

4. **Callbacks** — This ALM sets **`isCallbackOnSwap = false`**, so **`onSwapCallback`** is not used for extra post-swap logic.

**In short:** swaps are **HyperEVM DEX** trades against **vault inventory**, priced from the **Hyperliquid spot index** precompile, after the pool applies its **fee in bips**.

---

## How fees are composed

On-chain fees are **not** the multi-named “DeltaFlow” eight-component model in legacy docs. They come from **`BalanceSeekingSwapFeeModuleV3`** (`SwapFeeModuleV3.sol`) when wired as the pool’s swap fee module; otherwise the pool uses its **default fee in bips**.

When the fee module is active, **`getSwapFeeInBips`** roughly:

1. **Liquidity check** — Estimates output at spot and **reverts** if the vault cannot pay **`tokenOut`** (with buffer), similar in spirit to the ALM check.

2. **Imbalance component** — Reads vault **USDC (U)** and **PURR (P)** balances, derives spot **S** (USDC per PURR), compares value of both sides at spot, and measures **absolute deviation in bps** relative to the “balanced” side.

3. **Fee formula** — **`feeAddBps = deviationBps / 10`** (steps of **0.1%** of that deviation), then **`fee = baseFeeBips + feeAddBps`**, **clamped** to **`[minFeeBips, maxFeeBips]`**.

The **pool** converts **`feeInBips`** into **`amountInWithoutFee`**, passes that to the ALM, and settles **`effectiveFee`** in **`tokenIn`** with rounding rules as implemented in **`SovereignPool.swap`**.

---

## How trades are placed

| Layer | Behavior |
|-------|------------|
| **Pool / users** | Trades are **EVM transactions** (`swap`). No Hyperliquid CEX order is required for the user’s swap. |
| **Backend** (`server.py`) | Subscribes to **`Swap`** logs on **`WATCH_POOL`**. If **`ENABLE_HL_TRADING`** is **true**, it may send **Hyperliquid spot** orders (SDK `Exchange` / L2) on the configured **`SPOT_MARKET`** (e.g. PURR/USDC) to **rebalance** inventory vs a **mid** and **`REBALANCE_BAND`**. If **`ENABLE_HL_TRADING`** is **false**, it only records and broadcasts — **no** off-chain hedge trade. |

There is **no** on-chain **`HedgeExecutor`** or hedge FSM in the current **`contracts/src`** snapshot.

---

## Money routing: HyperEVM ↔ HyperCore

Implemented in **`SovereignVault`** using **`CoreWriterLib`** and **`PrecompileLib`**.

### Strategist / protocol operations

| Direction | Function(s) | Meaning |
|-----------|-------------|---------|
| **EVM → Core (balance only)** | `bridgeToCoreOnly` | USDC moves from the EVM vault into **HyperCore** without a vault deposit. |
| **EVM → Core vault (yield / allocation)** | `allocate` | `bridgeToCore` then `vaultTransfer(coreVault, true, …)` into a **Core vault**; **`allocatedToCoreVault`** / **`totalAllocatedUSDC`** track exposure. |
| **Core vault → EVM** | `deallocate` | `vaultTransfer(coreVault, false, …)` then `bridgeToEvm`. |
| **Core → EVM (no vault pull)** | `bridgeToEvmOnly` | When USDC is already positioned appropriately in Core. |

### During swaps

If the pool must pay USDC from the vault and **EVM USDC balance is insufficient**, **`sendTokensToRecipient`** (pool-authorized) may **`vaultTransfer(defaultVault, false, …)`** and **`bridgeToEvm`** so USDC is available on EVM, then transfer to the recipient.

### LP accounting

- **`getReserves()`** — USDC reserve includes **EVM USDC + `totalAllocatedUSDC`**; PURR is **EVM balance**.
- **`getReservesForPool`** — USDC side can also reflect **HyperCore spot USDC** via **`PrecompileLib.spotBalance`** for reserve views.

**PURR** in this design is primarily **ERC-20 on EVM** in the vault; **USDC** is the asset that **bridges** through CoreWriter-style flows.

---

## Related code paths

- `contracts/src/SovereignPool.sol` — `swap`, fee module hook, ALM quote, vault payouts.
- `contracts/src/SovereignALM.sol` — spot quote and vault liquidity check.
- `contracts/src/SwapFeeModuleV3.sol` — balance-seeking fee in bips.
- `contracts/src/SovereignVault.sol` — LP, Core bridge/allocate, `sendTokensToRecipient`.
- `backend/server.py` — swap log listener, optional HL spot rebalance.
