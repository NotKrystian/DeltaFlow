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

   and fill **`SPOT_INDEX_WETH`**, **`INVERT_WETH_PX`**, **`PERP_INDEX_WETH`** (real perp index for WETH), same way as PURR. This produces a **second** vault + pool + ALM + HedgeEscrow in one run.

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
     --rpc-url "$RPC" --fork-url "$RPC" \
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
   NEXT_PUBLIC_BACKEND_URL=http://127.0.0.1:8000
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

Check **`GET http://127.0.0.1:8000/health`** — you should see `watchPool`, `swapPollIntervalS`, `lastSwapBlockProcessed`, etc.

**Terminal B — frontend**

```bash
cd frontend
pnpm install
pnpm dev
```

Open the printed URL (usually `http://localhost:3000`). In RainbowKit, **switch the wallet to Hyperliquid testnet (998)**.

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

## Second pool (USDC / WETH)

After **`DEPLOY_USDC_WETH=true`**, **`sync_env_from_broadcast.py`** writes **`NEXT_PUBLIC_POOL_WETH`**, **`NEXT_PUBLIC_VAULT_WETH`**, **`NEXT_PUBLIC_ALM_WETH`**, **`NEXT_PUBLIC_WETH`**, **`NEXT_PUBLIC_HEDGE_ESCROW_WETH`**, etc. The **default UI** still points **`NEXT_PUBLIC_POOL` / `VAULT` / `ALM`** at the **primary (PURR) stack**.

**Ways to exercise the WETH stack:**

1. **Temporary env switch (same repo):** copy the **WETH** pool, vault, and ALM addresses from `.env.local` into **`NEXT_PUBLIC_POOL`**, **`NEXT_PUBLIC_VAULT`**, **`NEXT_PUBLIC_ALM`**, set **`NEXT_PUBLIC_HEDGE_ESCROW`** to **`NEXT_PUBLIC_HEDGE_ESCROW_WETH`**, and point **`NEXT_PUBLIC_USDC`** / **`NEXT_PUBLIC_WETH`** as in the synced file. Restart **`pnpm dev`**. The UI’s labels still say PURR in places unless you customize — use for **integration testing** only.
2. **CLI:** use **`cast send`** / scripts against **`POOL_WETH`** with the **USDC/WETH** pair ABI (advanced).

For **~$50 USDC + ~$50 WETH** notional: fund USDC as above, obtain testnet **WETH** per HL docs, then swap or deposit into the **WETH** vault using the path you chose.

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
