# Delta Flow

### Live Demo:

https://hyperliquid-hack-frontend.vercel.app/

Delta Flow is a highly composable and precise AMM inspired by the Valantis Sovereign Pool architecture.

While popular AMMs like Uniswap have started to integrate more functionality - for example, Uniswap v4 hooks - several constraints still exist. One example is reserve-based pricing. For large trades in low-liquidity pools, the pool price can deviate far from the true market price, resulting in high slippage costs for the end-user.

Delta Flow brings a new class of AMMs to market that: prices swaps based on spot prices, apply dynamic fees based pool value imbalances, allows for the allocation of excess liquidity to HyperCore vaults, and recalls liquidity from vaults to traders if the vault has insufficent liquidity.

![Delta Flow Logo](frontend/public/flow.png)

## GitBook documentation

Published documentation is maintained under [`docs/`](./docs/). The repo includes [`.gitbook.yaml`](./.gitbook.yaml) so **GitBook → Git sync** uses `./docs/` as the content root (`README.md` + `SUMMARY.md`). In GitBook, connect this repository and set the same root if the UI does not pick it up automatically.

## Delta Flow has four modules:

- Delta Vault
- Delta ALM
- Delta Swap-Fee
- Delta Liquidity Hedging Operator

## Delta Vault

A module which:

- Holds all pool assets
- Allows a strategist to deploy excess capital to a HyperCore Vault
- Provides the tokens for a swap in the Delta Pool
- Recalls the tokens from vault positions if the vault is short in existing reserves

Because pricing is anchored to spot markets, the pool does not naturally rebalance through arbitrage the way constant-product AMMs do. Without a rebalance mechanism, a pool could be drained of one token if it is repeatedly swapped out.

To counter this, Sovereign vault sells the token with higher reserves on the spot market for the token with less reserves.

## Delta ALM

A module which calculates the price for an asset to be swapped.

Delta ALM reads from the HyperEVM precompile contract to get the mid spot price, calculates the total value of the other token needed for the trade (USDC in our product), and returns this amount for the user to swap in.

This prevents the reserve-based price drift described above.

## Delta Swap-Fee

A module which dynamically calculates fees based on deviations within pool reserves.

The pool aims to maintain a 1:1 USDC value ratio:

- the USDC value of token X reserves must equal the USDC value of token Y reserves.

To further avoid deviations in pool balances, we apply a linearly increasing fee for every 0.1% deviation.

Target condition (healthy state):

```
USDC_value(base reserves) ≈ USDC_value(USDC reserves)  (at spot)
```

## Delta Liquidity Hedging Operations

**On-chain (vault-backed pools):** Before **`tokenOut`**, **`SovereignVault.processSwapHedge`** runs: **HyperCore perp** IOC via **CoreWriter**, sized to the **base** leg (the non-USDC pool asset). The pool and vault share **`hedgePerpAssetIndex`**; misconfiguration reverts swaps. **`_netHedgePosition`** may **reduce-only unwind** first, then open residual size; the vault exposes **`lastHedgeLeg`** for ops. With batching (**`useMarkBasedMinHedgeSz`** or **`minPerpHedgeSz > 0`**), sub-threshold hedges **escrow** **`tokenOut`** until the bucket clears, then **IOC + payouts**. Full detail: [`docs/architecture/current-implementation.md`](./docs/architecture/current-implementation.md).

**Strategist (Core):** Run **`bootstrapHyperCoreAccount`** (min USDC) in a **dedicated tx** before heavy CoreWriter use; **`bridgeInventoryTokenToCore`**, **`fundCoreWithHype`**, **`forceFlushHedgeBatch`**, **`pullPerpUsdcToEvm`**, **`pullCoreSpotTokenToEvm`** — see the same doc and the **Strategist** page in the app.

**Optional API wallet / off-chain:** A strategist can still use an approved agent for additional spot or perp operations on HyperCore beyond this automatic path.

**HedgeEscrow (user spot flow):** Users can open separate **spot** hedges via **`HedgeEscrow`** (CoreWriter spot limit orders). That path is distinct from the vault’s per-swap **perp** hedge.

Inventory and fee dynamics still follow the same high-level goal as the swap-fee module—keep quoted prices aligned with spot—documented in [`docs/`](./docs/).

### Frontend

```bash
pnpm install
pnpm dev
```

### How to deploy

**Chain:** Hyperliquid **testnet** HyperEVM (**998**). Authoritative env template: [`deploy/testnet.env.example`](./deploy/testnet.env.example). Copy it to the repo root as **`.env`** and fill **`PRIVATE_KEY`**, **`POOL_MANAGER`**, **`SPOT_INDEX_PURR`** (from [`ReadSpotIndex.s.sol`](./contracts/script/ReadSpotIndex.s.sol)), plus factory/verifier addresses required by your deployment. **`DEPLOY_DELTAFLOW_FEE`** defaults to **`true`** (deploys **`FeeSurplus`**, **`DeltaFlowRiskEngine`**, **`DeltaFlowCompositeFeeModule`**); set **`false`** for **`BalanceSeekingSwapFeeModuleV3`** only. To force ALM quotes from perp mark (useful on illiquid testnet spot), set **`USE_PERP_PRICE_FOR_QUOTE_PURR`** / **`USE_PERP_PRICE_FOR_QUOTE_WETH`**. For debug deployments, set **`SWAP_FEE_MODULE_TIMELOCK_SEC=0`** (immediate fee-module rewires); before production launch, restore **`259200`** (3 days).

**Indices and asset ids** (`10000 + spotIndex`, token indices, perp vs spot): [`docs/deployment/testnet-asset-ids.md`](./docs/deployment/testnet-asset-ids.md). For **`DeployAll`** with an external vault, set **`PERP_INDEX_PURR`** (or WETH) to the real **perp** index for the base asset; see [`deploy/testnet.env.example`](./deploy/testnet.env.example) and [`docs/deployment/pairs-and-scripts.md`](./docs/deployment/pairs-and-scripts.md).

## End-to-end runbook

Step-by-step: **deploy → start backend + frontend → trade → ~$50 test portfolio (USDC/PURR + notes for USDC/WETH)** — see **[`docs/getting-started/full-stack-runbook.md`](./docs/getting-started/full-stack-runbook.md)**.

## Deployment

**Recommended (one step — deploy + write `frontend/.env.local` and `backend/.env`):**

```shell
forge clean && forge build
./scripts/deploy_all_testnet.sh
```

This runs `forge script ... DeployAll ... --broadcast` then **`python3 scripts/sync_env_from_broadcast.py`**, which reads `broadcast/DeployAll.s.sol/998/run-latest.json` and merges contract addresses into those env files (existing keys like `SWAP_POLL_INTERVAL_S` / `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` are preserved).

Manual equivalent:

```shell
RPC=https://rpc.hyperliquid-testnet.xyz/evm
forge script contracts/script/DeployAll.s.sol:DeployAll \
  --rpc-url "$RPC" \
  --fork-block-number "$(cast block-number --rpc-url "$RPC")" \
  --broadcast -vvvv
RPC_URL="$RPC" python3 scripts/sync_env_from_broadcast.py
```

`DeployAll` uses **`PrecompileLib.getTokenIndex`** (registry) for HedgeEscrow’s Core token index; the spot **universe** index comes from your **`SPOT_INDEX_*`** env vars (the on-chain `getSpotIndex` path hits precompile **`0x080C`**, which Forge’s simulator cannot execute). Prefer **`./scripts/deploy_all_testnet.sh`** (`--rpc-url` + `--fork-block-number` for realistic forked state).

See [`scripts/sync_env_from_broadcast.py`](./scripts/sync_env_from_broadcast.py) for flags (`--dry-run`, custom paths).

**Broadcast error `exceeds block gas limit` (-32603):** HyperEVM uses [dual blocks](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm/dual-block-architecture): **fast blocks ~2–3M gas** (default) vs **slow “big” blocks ~30M gas**. Large contract deployments (for example `SovereignVault`) need **big blocks**. Enable **`usingBigBlocks`** for your deployer via Core action `evmUserModify`, or use a community toggle (search “HyperEVM big blocks toggle”). Until this is set, transactions that need more gas than a small block’s limit are rejected.

**Broadcast error `nonce too high` (-32003):** On many public RPCs the **first transaction in each multi-tx `forge script` broadcast** (often shown as sequence 1 in the batch) fails if the sender does not wait for confirmations between txs. By default, **`./scripts/deploy_all_testnet.sh`** uses **`--slow` on every** `forge script --broadcast` (each tx confirms before the next) **and** splits out the SovereignVault deploy as its own run. To broadcast faster without waiting for receipts, set **`DEPLOY_FAST=1`** (or **`DEPLOY_SLOW=0`**). Use **`DEPLOY_SINGLE_SHOT=1`** for a single **`run()`** (legacy one-shot). If some txs already landed, continue with **`forge script contracts/script/DeployAll.s.sol:DeployAll --resume --rpc-url "$RPC" --broadcast`**. Do not delete `broadcast/` blindly if you need **`--resume`**.

**If errors persist:** the node may disagree on **pending** vs **latest** nonce (load-balanced RPCs). Use **`./scripts/check_nonce.sh <deployer>`** — if **`latest` ≠ `pending`**, wait for the mempool to drain, or use **one stable RPC URL** for both `forge script` and wallet.

Optional: `./check_deploy.sh` with **`POOL`**, **`VAULT`**, **`ALM`**, **`SWAP_FEE_MODULE`**, **`DEPLOYER`**, **`POOL_MANAGER`** exported to match your broadcast.

## Backend Server

```shell
$ pip install python-dotenv fastapi uvicorn web3
$ python backend/server.py
```

### Live Demo:

https://hyperliquid-hack-frontend.vercel.app/
