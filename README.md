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
- Delta Liqudity Hedging Operator

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
USDC/PURR * spot price
```

## Delta Liquidity Hedging Operations

**On-chain (vault-backed pools):** Before **`tokenOut`**, **`SovereignVault.processSwapHedge`** runs: **HyperCore perp** IOC via **CoreWriter**, sized to the PURR leg. The pool and vault share **`hedgePerpAssetIndex`**; misconfiguration reverts swaps. With **`minPerpHedgeSz > 0`**, sub-minimum hedges **escrow** the quoted output until the hedge bucket reaches the HL minimum, then **one IOC** pays **all** queued recipients in that batch (a large swap can trigger the batch). With **`minPerpHedgeSz == 0`**, each swap gets an immediate IOC and immediate **`tokenOut`**. Full detail: [`docs/architecture/current-implementation.md`](./docs/architecture/current-implementation.md).

**Optional API wallet / off-chain:** A strategist can still use an approved agent for additional spot or perp operations on HyperCore beyond this automatic path.

**HedgeEscrow (user spot flow):** Users can open separate **spot** hedges via **`HedgeEscrow`** (CoreWriter spot limit orders). That path is distinct from the vault’s per-swap **perp** hedge.

Inventory and fee dynamics still follow the same high-level goal as the swap-fee module—keep quoted prices aligned with spot—documented in [`docs/`](./docs/).

### Frontend

```bash
pnpm install
pnpm dev
```

### How to deploy

**Chain:** Hyperliquid **testnet** HyperEVM (**998**). Authoritative env template: [`deploy/testnet.env.example`](./deploy/testnet.env.example). Copy it to the repo root as **`.env`** and fill **`PRIVATE_KEY`**, **`POOL_MANAGER`**, **`SPOT_INDEX_PURR`** (from [`ReadSpotIndex.s.sol`](./contracts/script/ReadSpotIndex.s.sol)), plus factory/verifier addresses required by your deployment. **`DEPLOY_DELTAFLOW_FEE`** defaults to **`true`** (deploys **`FeeSurplus`**, **`DeltaFlowRiskEngine`**, **`DeltaFlowCompositeFeeModule`**); set **`false`** for **`BalanceSeekingSwapFeeModuleV3`** only.

**Indices and asset ids** (`10000 + spotIndex`, token indices, perp vs spot): [`docs/deployment/testnet-asset-ids.md`](./docs/deployment/testnet-asset-ids.md). For **`DeployAll`** with an external vault, set **`PERP_INDEX_PURR`** (or WETH) to the real **perp** index for the base asset; see [`deploy/testnet.env.example`](./deploy/testnet.env.example) and [`docs/deployment/pairs-and-scripts.md`](./docs/deployment/pairs-and-scripts.md).

## Deployment

**Recommended (one step — deploy + write `frontend/.env.local` and `backend/.env`):**

```shell
forge clean && forge build
./scripts/deploy_all_testnet.sh
```

This runs `forge script ... DeployAll ... --broadcast` then **`python3 scripts/sync_env_from_broadcast.py`**, which reads `broadcast/DeployAll.s.sol/998/run-latest.json` and merges contract addresses into those env files (existing keys like `ALCHEMY_WSS_URL` / `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` are preserved).

Manual equivalent:

```shell
forge script contracts/script/DeployAll.s.sol:DeployAll \
  --rpc-url https://rpc.hyperliquid-testnet.xyz/evm \
  --broadcast -vvvv
RPC_URL=https://rpc.hyperliquid-testnet.xyz/evm python3 scripts/sync_env_from_broadcast.py
```

See [`scripts/sync_env_from_broadcast.py`](./scripts/sync_env_from_broadcast.py) for flags (`--dry-run`, custom paths).

Optional: `./check_deploy.sh` with **`POOL`**, **`VAULT`**, **`ALM`**, **`SWAP_FEE_MODULE`**, **`DEPLOYER`**, **`POOL_MANAGER`** exported to match your broadcast.

## Backend Server

```shell
$ pip install dotenv asyncio fastapi web3 websockets
$ python backend/server.py
```

### Live Demo:

https://hyperliquid-hack-frontend.vercel.app/
