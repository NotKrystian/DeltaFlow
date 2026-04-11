# Liquidity

Liquidity providers (LPs) deposit tokens into DeltaFlow's vault and receive **DFLP** shares in return. These shares represent a proportional claim on the vault's total value. As DeltaFlow has balances across HyperEVM and HyperCore, this is based on the protocols full net asset value (NAV) across EVM holdings, capital deployed to HyperCore yield vaults, and the P\&L of active hedge positions.

## Depositing

DeltaFlow uses value-based share issuance. Deposits are accepted in any composition of the two tokens. For example, only USDC, the base asset, or a mix. The vault prices the deposit at Hyperliquid's spot index, and mints shares proportional to the value deposited relative to the pool's current NAV.

## What backs LP shares

In a standard AMM, the pool's value is the sum of its token reserves. DeltaFlow's vault operates across multiple layers:

- **EVM balances** — tokens held directly in the vault contract
- **HyperCore vault allocations** — USDC deployed to yield-bearing Core vaults (e.g. HLP), earning passive yield
- **Perp hedge P\&L** — unrealised gains and losses on the vault's active hedge positions on HyperCore

Share price reflects all three. As the vault earns yield and hedge P\&L accrues, the NAV per share rises.

## Impermanent loss

In a traditional AMM, an LP's position is tied to the pool's reserve ratio. When the price of the base token moves, the pool rebalances through arbitrage, leaving the LP holding less of the appreciating asset than if they had simply held. This is impermanent loss.

DeltaFlow reduces this exposure through its [swap hedging model](../architecture/overview.md). Each swap that shifts the vault's token composition is offset by a corresponding perp position on HyperCore. The vault's directional exposure stays bounded, so LP value is less sensitive to price movement in either direction.

## Fees

DeltaFlow's fee model is dynamic. Fees respond to the vault's current inventory imbalance, the cost of executing the perp hedge, and prevailing market conditions. When a swap increases the vault's risk — moving it further from balance or requiring a new hedge — fees are higher. When a swap reduces existing risk — partially unwinding an open hedge — fees are lower.

This means LPs are compensated proportionally to the risk each trade creates, rather than collecting the same fee regardless of whether the pool is balanced or stressed.

## Withdrawing

LPs burn DFLP shares and receive a pro-rata portion of the vault's EVM token balances. Core vault allocations and hedge P\&L continuously flow back to the EVM vault over time, so the withdrawal value converges with the full NAV as positions settle.
