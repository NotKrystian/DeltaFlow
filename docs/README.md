# Welcome

## **Introduction**

In it's [Current implementation](architecture/current-implementation.md), DeltaFlow is an automated-market maker which allows traders to swap cryptocurrencies through on-chain liquidity, while overcoming key limitations of traditional AMMs.

### Core Features&#x20;

To read a more detailed explanation, see [Architecture](/broken/pages/AX1fHLcc9kWX9CoNbzxW).

#### Spot-Index Pricing

The dominant approach for AMMs has been to price swaps based on the underlying pool reserves. If a pool contains 2 ETH and 4000 USDC, the ETH is priced at \~2000 USDC each. In practice, if a trader wanted to purchase 1 ETH from this pool, they would pay \~4012 USDC. This is because most AMMs use the constant product formula, which aims to maintain the value of the product of each token reserve before and after a swap. As a result, when making large trades in illiquid pools, execution price often exceeds the value a trader would pay on centralised or highly liquid markets.&#x20;

DeltaFlow decouples price from token reserves. Using Hyperliquid's Precompiles, DeltaFlow quotes prices from Hyperliquid's order book — a deep, highly liquid market. Traders are no longer forced up the constant-product curve because on-chain liquidity is shallow.

#### Swap Hedging

One of our core propositions of DeltaFlow is to materially reduce impermant loss for liquidity providers (LPs). In traditional AMMs, an LPs position is tied to the pools token reserves, so changes in its token composition can cause the value of LP's withdrawal to be lower than if they simply held the tokens.

DeltaFlow address this by hedging inflow swaps on the HyperCore perpetual market via the CoreWriter smart contract. When a trade changes the pools composition, DeltaFlow opens or adjusts an offsetting position on HyperCore so that the protocol neutralises the market risk created by the swap.&#x20;

## Docs Guide

| If you want to…                                                  | Go to                                                            |
| ---------------------------------------------------------------- | ---------------------------------------------------------------- |
| **What the code does today** (fees, swaps, Core, escrow)         | [Current implementation](architecture/current-implementation.md) |
| Deploy **primary** vs **secondary** USDC/base stack              | [Pairs and deployment scripts](deployment/pairs-and-scripts.md)  |
| **Spot indices, token ids, `10000+spotIndex`**                   | [Testnet asset IDs](deployment/testnet-asset-ids.md)             |
| Run the stack locally                                            | [Quick start](getting-started/quick-start.md)                    |
| **Deploy → backend + frontend → trades → fund a test portfolio** | [Full stack runbook](getting-started/full-stack-runbook.md)      |
| System overview                                                  | [Architecture](architecture/overview.md)                         |
| On-chain components                                              | [Protocol contracts](protocol/contracts.md)                      |
| Backend & API                                                    | [Backend API](operations/backend-api.md)                         |

