# Hyperliquid testnet — asset IDs and addresses

**Network:** HyperEVM on Hyperliquid **testnet**, chain ID **998**.  
**RPC:** `https://rpc.hyperliquid-testnet.xyz/evm`

This page lists **canonical token addresses** used in repo templates and explains how **spot indices**, **Core token indices**, and **limit-order asset ids** relate. Always confirm indices on-chain with [`ReadSpotIndex.s.sol`](../../contracts/script/ReadSpotIndex.s.sol) before a production deploy.

## Canonical testnet ERC-20 addresses

| Token | Address |
|-------|---------|
| **USDC** | `0x2B3370eE501B4a559b57D449569354196457D8Ab` |
| **PURR** | `0xa9056c15938f9aff34CD497c722Ce33dB0C2fD57` |
| **WETH** | `0x5a1A1339ad9e52B7a4dF78452D5c18e8690746f3` |

These match [`deploy/testnet.env.example`](../../deploy/testnet.env.example).

## Spot universe index (`spotIndex`)

For a token listed on Hyperliquid **spot**, **`PrecompileLib.getSpotIndex(token)`** returns that market’s index in **`spotMeta.universe`** (a **uint64**). This is **not** the same as a **perpetual** “universe” id from `meta` (for example, PURR is often **125** in perp metadata — that value is **irrelevant** for spot precompile pricing and for `HedgeEscrow` wiring).

**Deploy:** set **`SPOT_INDEX_PURR`** / **`SPOT_INDEX_WETH`** in your forge env to the value logged as **`PURR spotIndex (universe)`** when you run **`ReadSpotIndex`** (or read it from a successful deploy script that logs `Spot index:`).

## Limit orders and `spotAssetIndex`

For **spot** order placement via CoreWriter-style APIs, Hyperliquid uses:

```text
spotAssetIndex = 10000 + spotIndex
```

where **`spotIndex`** is the same **`getSpotIndex`** universe index as above. [`HedgeEscrow`](../../contracts/src/HedgeEscrow.sol) and deploy scripts use this **`10000 + spotIdx`** form for the **`spotAsset`** field.

## Core token index (backend `PURR_TOKEN_INDEX`)

**`PrecompileLib.getTokenIndex(baseToken)`** returns the **Core token index** for that EVM address (used for **`spotBalance`** and related reads). The backend env **`PURR_TOKEN_INDEX`** must hold this value for the **base** asset (PURR, WETH, …). It is **not** the perp universe id and **not** `10000 + spotIndex`.

Deploy logs print **`BASE_TOKEN_INDEX (backend PURR_TOKEN_INDEX)=`** when **`DEPLOY_HEDGE_ESCROW=true`**.

## DeltaFlow composite fee module — perp and BBO

When **`DEPLOY_DELTAFLOW_FEE=true`** (default in [`deploy/testnet.env.example`](../../deploy/testnet.env.example)):

- **`PERP_INDEX_*`** — Set to **`4294967295`** (`2^32 - 1`, `type(uint32).max`) to **disable** perp leg reads in the composite fee module if you do not rely on perp metadata for that pair.
- **`SPOT_ASSET_BBO_*`** — **`0`** means “derive BBO asset as **`10000 + SPOT_INDEX_*`**” (same rule as above). Override only if you intentionally point BBO to another asset id.

## Commands

**Discover indices for TOKEN0 / TOKEN1:**

```bash
export TOKEN0=0xa9056c15938f9aff34CD497c722Ce33dB0C2fD57
export TOKEN1=0x2B3370eE501B4a559b57D449569354196457D8Ab
forge script contracts/script/ReadSpotIndex.s.sol:ReadSpotIndex \
  --rpc-url https://rpc.hyperliquid-testnet.xyz/evm -vvv
```

Then copy **`SPOT_INDEX_PURR`** (and **`SPOT_INDEX_WETH`** for WETH) into your root `.env` for **`forge script DeployAll`**.

## Related

- [Pairs and deployment scripts](pairs-and-scripts.md)
- [Quick start](../getting-started/quick-start.md)
- [Backend API](../operations/backend-api.md)
