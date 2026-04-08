# Quick start

Prerequisites: **Foundry**, **Node.js ≥ 18**, **Python ≥ 3.10**.

## 1. Clone and backend env

```bash
git clone <your-repo-url> && cd DeltaFlow
cp backend/.env.example backend/.env
# Fill in: ALCHEMY_WS_URL, EVM_RPC_HTTP_URL, STRATEGIST_EVM_PRIVATE_KEY,
# SOVEREIGN_VAULT, WATCH_POOL, USDC_ADDRESS, WETH_ADDRESS
```

## 2. Build contracts

```bash
forge build --force
```

## 3. Deploy (Hyperliquid testnet example)

```bash
forge script contracts/script/DeployDeltaFlow.s.sol:DeployDeltaFlow \
  --rpc-url https://rpc.hyperliquid-testnet.xyz/evm \
  --broadcast -vvvv
```

Use `DeployAll.s.sol` if you follow the older full deploy path. Set `PRIVATE_KEY` and script env vars as required by each script.

## 4. Backend

```bash
cd backend
pip install -r requirements.txt
python server.py
# Or: docker build -t deltaflow-backend . && docker run --env-file .env -p 8000:8000 deltaflow-backend
```

## 5. Frontend

```bash
cd frontend
cp .env.example .env.local   # NEXT_PUBLIC_* contract addresses + WalletConnect project ID
pnpm install
pnpm dev
```

## Optional: Python deploy helper

After `forge build`, you can use the root `deploy.py` for vault/ALM/fee-module flows (see script help: `python deploy.py --help`).
