# Full stack: deploy, run servers, trade, and fund a test portfolio

This guide takes you from **zero** to **contracts deployed**, **backend + frontend running**, **a few swaps**, and roughly **~$50 notional per side** on **USDC/PURR** plus notes for a **second USDC/WETH** stack. Target chain: **Hyperliquid testnet HyperEVM (chain ID `998`)**.

## What you need installed

| Tool | Role |
|------|------|
| **Foundry** (`forge`, `cast`) | Build and deploy contracts |
| **Node.js ≥ 18** + **pnpm** | Frontend |
| **Python ≥ 3.10** + **pip** | Backend |
| **Wallet** with a **testnet private key** | Deploy and trade |

You also need **native gas** on HyperEVM testnet for transactions, and **testnet USDC** (and optionally base assets) from Hyperliquid’s testnet flows. Use current [Hyperliquid docs](https://hyperliquid.xyz/) for the official faucet / bridge steps; addresses change over time.

## One-time: repo and deploy configuration

1. **Clone and build contracts**

   ```bash
   cd DeltaFlow
   forge build --force
   ```

2. **Configure the forge deploy env** — copy the template to the **repo root** as **`.env`** (Foundry reads it for `forge script`):

   ```bash
   cp deploy/testnet.env.example .env
   ```

3. **Fill required variables** in **`.env`** (minimum):

   | Variable | Notes |
   |----------|--------|
   | `PRIVATE_KEY` | Deployer key (no `0x` prefix is fine if your tooling accepts it; match Foundry conventions). |
   | `POOL_MANAGER` | Your protocol pool manager address (see `deploy/testnet.env.example`). |
   | `SPOT_INDEX_PURR` | Run `forge script contracts/script/ReadSpotIndex.s.sol` on testnet with `TOKEN0`/`TOKEN1` set to PURR/USDC pair, then set the logged spot index. |
   | `PERP_INDEX_PURR` | **Real** Hyperliquid **perp universe** index for the PURR market — **not** `4294967295` for the standard vault-backed `DeployAll` path (see [Testnet asset IDs](../deployment/testnet-asset-ids.md)). |
   | `USDC`, `PURR` | Canonical testnet token addresses are already in `deploy/testnet.env.example` unless HL changes them. |

4. **Optional: deploy USDC/WETH in the same broadcast** — in **`.env`** set:

   ```bash
   DEPLOY_USDC_WETH=true
   ```

   and fill **`SPOT_INDEX_WETH`**, **`INVERT_WETH_PX`**, **`PERP_INDEX_WETH`** (real perp index for WETH), same way as PURR. This produces a **second** vault + pool + ALM + HedgeEscrow.

   With **`DEPLOY_USDC_WETH=true`**, `./scripts/deploy_all_testnet.sh` defaults to a **two-phase** broadcast: it deploys **USDC/PURR** first (keep **big blocks** on the deployer), **pauses** so you can switch the wallet to **small blocks** (~0.33s block time), then deploys **USDC/WETH**. Set **`DEPLOY_PAUSE_BETWEEN_STACKS=0`** in the shell if you want both stacks in a single `run()` without pausing.

5. **Deploy and sync app env files**

   From the repo root:

   ```bash
   ./scripts/deploy_all_testnet.sh
   ```

   This runs `forge script contracts/script/DeployAll.s.sol:DeployAll --broadcast` and then **`python3 scripts/sync_env_from_broadcast.py`**, which merges addresses into **`frontend/.env.local`** and **`backend/.env`** from `broadcast/DeployAll.s.sol/998/run-latest.json`.

   **Manual equivalent** (include **fork** so `PrecompileLib` / HedgeEscrow simulation works on HL precompiles):

   ```bash
   RPC=https://rpc.hyperliquid-testnet.xyz/evm
   forge script contracts/script/DeployAll.s.sol:DeployAll \
     --rpc-url "$RPC" \
     --fork-block-number "$(cast block-number --rpc-url "$RPC")" \
     --broadcast -vvvv
   RPC_URL="$RPC" CHAIN_ID=998 \
     python3 scripts/sync_env_from_broadcast.py --rpc-url "$RPC"
   ```

6. **Frontend secrets** — `sync` does **not** create `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID`. Copy **`frontend/.env.example`** to **`frontend/.env.local`** if you do not already have one, and set:

   - `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` — from [WalletConnect Cloud](https://cloud.walletconnect.com).

   Re-run **`sync_env_from_broadcast.py`** after a new deploy so contract addresses stay merged (existing keys like WalletConnect are preserved).

7. **Backend URL for the Hedge tab** — in **`frontend/.env.local`** set:

   ```bash
   NEXT_PUBLIC_BACKEND_URL=http://127.0.0.1:3000
   ```

   (Use your real backend URL in production.)

## Start the servers

**Terminal A — backend**

```bash
cd backend
pip install -r requirements.txt
# Ensure backend/.env exists (sync created it) and CHAIN_ID / RPC / pool / escrow match deploy
python server.py
```

Check **`GET http://127.0.0.1:3000/health`** — you should see `watchPool`, `swapPollIntervalS`, `lastSwapBlockProcessed`, etc.

**Terminal B — frontend**

The API uses **port 3000** by default, so run Next.js on **3001** (or set **`PORT`** / **`NEXT_PUBLIC_BACKEND_URL`** consistently):

```bash
cd frontend
pnpm install
pnpm dev -- -p 3001
```

Open **`http://localhost:3001`**. In RainbowKit, **switch the wallet to Hyperliquid testnet (998)**.

## Make a few trades (USDC / PURR)

1. **Fund the wallet** with testnet **USDC** and enough **native token** for gas (per current HL testnet instructions).
2. Open **Trade** → **Swap**. Approve **USDC** / **PURR** to the pool as prompted, then swap a small amount **USDC → PURR** and optionally **PURR → USDC** so you see both directions succeed.
3. Open **LP** (`/lp`) and **deposit** a small amount via **`depositLP`** (approve vault, then deposit) if you want LP exposure. The app also has **Docs** → **LP provider** at `/docs/lp` for step-by-step copy.

## ~$50 notional per “side” (illustrative)

Amounts are **illustrative** — use whatever matches your testnet balance.

- **Rough goal:** about **$50 USDC** and about **$50** worth of **PURR** (at spot) in your wallet, and similar **USDC + WETH** notional for the second pool if you use it.
- **USDC:** acquire testnet USDC from the official process until you have **≥ 50 USDC** (6 decimals).
- **PURR:** swap **~50 USDC → PURR** on the **Swap** tab (or until your PURR balance is ~$50 at the UI’s implied price). Keep some USDC left for fees and further swaps.
- **LP (optional):** on **`/lp`**, deposit a mix of USDC and PURR so the vault holds inventory; your share % and value estimates appear on that page.

## Second pool (secondary USDC / base)

After **`DEPLOY_USDC_WETH=true`**, **`sync_env_from_broadcast.py`** writes **`NEXT_PUBLIC_POOL_WETH`**, **`NEXT_PUBLIC_VAULT_WETH`**, **`NEXT_PUBLIC_ALM_WETH`**, **`NEXT_PUBLIC_WETH`**, **`NEXT_PUBLIC_HEDGE_ESCROW_WETH`**, etc.

**Recommended:** Use the **header market switcher** (primary vs secondary) — no manual env swapping. Set optional **`NEXT_PUBLIC_PRIMARY_BASE_SYMBOL`** and **`NEXT_PUBLIC_SECONDARY_BASE_SYMBOL`** so buttons and copy match your deployed assets (defaults: **PURR** / **WETH**).

**Alternatives:**

1. **Temporary single-env override:** point **`NEXT_PUBLIC_POOL` / `VAULT` / `ALM`** at the secondary addresses only if you need a single-market build (integration testing).
2. **CLI:** **`cast send`** / scripts against **`POOL_WETH`** with the pool ABI.

For **~$50** notional on the secondary side: fund **USDC** and the **secondary base** token per HL testnet flows, then swap or deposit while the switcher is on **secondary**.

## Strategist after redeploy

If you use **CoreWriter**-heavy flows, run **`bootstrapHyperCoreAccount`** (min 1 USDC) on the vault **once** in its own transaction, then optional **`bridgeInventoryTokenToCore`**, **`fundCoreWithHype`**, etc. See [Current implementation — Strategist / protocol operations](../architecture/current-implementation.md) and the in-app **Strategist** page.

## Troubleshooting

| Issue | What to check |
|--------|----------------|
| `forge script` reverts on deploy | `PERP_INDEX_*` must match a real perp index for the vault-backed path; spot indices in `SPOT_INDEX_*`; `POOL_MANAGER` set. |
| `sync_env_from_broadcast.py` fails `PURR_TOKEN_INDEX` | Run with **`RPC_URL`** set so `cast` can read **`HedgeEscrow`**, or ensure broadcast JSON includes constructor args. |
| Backend exits on import | All of **`backend/.env.example`** required keys must be non-empty (sync fills most). |
| Frontend wrong pool | Re-run sync after deploy; restart Next.js; clear cache. |
| Hedge tab shows no data | **`NEXT_PUBLIC_BACKEND_URL`** must match running backend; CORS **`CORS_ORIGINS`** in **`backend/.env`**. |

## Related docs

- [Quick start](quick-start.md) — shorter checklist  
- [Pairs and deployment scripts](../deployment/pairs-and-scripts.md)  
- [Testnet asset IDs](../deployment/testnet-asset-ids.md)  
- [Backend API](../operations/backend-api.md)  
- [Current implementation](../architecture/current-implementation.md)  
