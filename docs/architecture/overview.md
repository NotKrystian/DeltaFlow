# System overview

{% hint style="success" %}
**Authoritative detail for the current repo:** [Current implementation — trading, fees, routing](current-implementation.md) (spot-index pricing, fees, vault ↔ Core, **hedging**).
{% endhint %}

DeltaFlow is optimised for execution price and reduced impermanent loss for liquidity providers (LPs). It achieves this by the following attributes:

* Order-book pricing&#x20;
* Swap hedging between HyperEVM and HyperCore

### Hedging model&#x20;

* **Perpetuals:** For external-vault pools, **`SovereignPool`** calls **`SovereignVault.processSwapHedge`** before paying **`tokenOut`**. The vault sends perp IOC (immediate or cancel) orders via **CoreWriter** sized to hedge the swap's base-asset exposure. If the hedge needs to reverse an existing position, the vault first unwinds the reduce-only orders.&#x20;
  * When batching is enabled, hedges below a defined threshold are not executed immediately. Instead, swap outputs are escrowed until the batch threshold is reached, at which point the vault submits the IOC hedge and releases the batch payout.&#x20;
  * To prevent mismatches, the pool’s immutable hedgePerpAssetIndex must equal the vault’s configured asset index; otherwise, the swap reverts. See Current implementation — On-chain per-swap perp hedge. See [Current implementation — On-chain per-swap perp hedge](current-implementation.md#on-chain-per-swap-perp-hedge-and-batch-queue).
* **HyperCore spot:** HyperCore spot is used in two cases. First, it is used when the EVM-based inventory is insufficient to fill a swap (`sendTokensToRecipient`). Second, it is used by **`HedgeEscrow`**  for user-initiated spot limit orders and subsequent claims.&#x20;

In its current version, **`HedgeEscrow`** exposes CoreWriter spot limit orders and claim flows.  Vault swap perp hedging is implemented in **`SovereignVault`** — see [Current implementation](current-implementation.md).

### HyperEVM — HyperCore Interaction

```mermaid
flowchart LR
  subgraph evm [HyperEVM]
    U[User / wallet]
    P[SovereignPool]
    A[SovereignALM]
    F[Swap fee module]
    V[SovereignVault]
    U --> P
    P --> F
    P --> A
    P --> V
  end
  subgraph core [HyperCore]
    PC[Precompiles / CoreWriter]
  end
  A <--> PC
  V <--> PC
```

## On-chain

### HyperEVM

| Layer                                                                      | Role                                                                                                                                                                                                                                                                                                                    |
| -------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **SovereignPool**                                                          | Valantis-style pool: swap routing, swap fee module, ALM quote, vault token flows.                                                                                                                                                                                                                                       |
| **SovereignALM**                                                           | Quotes **USDC vs base** from the Hyperliquid **spot index** (`PrecompileLib`); **`getSpotPriceUsdcPerBase`**; enforces vault liquidity for `tokenOut`.                                                                                                                                                                  |
| **DeltaFlowCompositeFeeModule** + **FeeSurplus** + **DeltaFlowRiskEngine** | Default in **`DeployAll`** when **`DEPLOY_DELTAFLOW_FEE=true`**: multi-component fee + surplus routing + risk gate.                                                                                                                                                                                                     |
| **BalanceSeekingSwapFeeModuleV3**                                          | Alternative `ISwapFeeModule` when **`DEPLOY_DELTAFLOW_FEE=false`**: **base fee + imbalance** vs spot-valued inventory.                                                                                                                                                                                                  |
| **SovereignVault**                                                         | LP token (`DFLP`), deposits/withdrawals, **USDC** bridge/allocate/deallocate via **CoreWriter**, strategist **bootstrap / inventory→Core / HYPE**, **`forceFlushHedgeBatch`**, pull helpers, `sendTokensToRecipient` / **`processSwapHedge`** (perp IOC + **`lastHedgeLeg`** + optional escrow + **`sz`** batch queue). |
| **HedgeEscrow** (always deployed per stack)                                | CoreWriter **spot** orders + claim path; **no** API wallet execution. Distinct from vault **per-swap perp** hedge.                                                                                                                                                                                                      |

### HyperCore

Oracle, mark, BBO, spot balance, and **CoreWriter** precompiles sit under Hyperliquid’s stack; testnet addresses are listed in the root **README** where applicable.

## Off-chain

| Component              | Role                                                                                                                                                 |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Backend (FastAPI)**  | Swap log subscription, REST + `/ws`, **`/escrow/trades`**, **`HEDGE_ESCROW`** + **`PURR_TOKEN_INDEX`** required. Does **not** execute HL API orders. |
| **Frontend (Next.js)** | Wallet on chain `998`, swap, liquidity, and **Hedge** (`NEXT_PUBLIC_HEDGE_ESCROW` from deploy sync).                                                 |

## Roadmap / extended design

Additional modules (for example **circuit breaker** or richer **netting** across buy/sell hedge queues) may be layered beside the default stack; the **DeltaFlow** fee and risk contracts under `contracts/src/deltaflow/` are the current multi-component fee path — see [current implementation](current-implementation.md).

**`DeployAll`** always deploys **`HedgeEscrow`** per market stack. Deployments can target any **USDC/base** pair (e.g. PURR, WETH) using the same contract family with separate deploys (see [Pairs and deployment scripts](../deployment/pairs-and-scripts.md)).

**Frontend:** The app switches between **primary** and **secondary** stacks when **`NEXT_PUBLIC_POOL_WETH`** (etc.) is set; **base** symbols come from **`NEXT_PUBLIC_PRIMARY_BASE_SYMBOL`** / **`NEXT_PUBLIC_SECONDARY_BASE_SYMBOL`**.
