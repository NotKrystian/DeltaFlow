import { ADDRESSES } from "@/contracts";

export const ZERO = "0x0000000000000000000000000000000000000000" as const;

/** Primary pool (env `NEXT_PUBLIC_POOL`) vs optional secondary stack (`NEXT_PUBLIC_POOL_WETH`). */
export type MarketId = "primary" | "secondary";

export type TokenMeta = {
  address: `0x${string}`;
  symbol: string;
  decimals: number;
  name: string;
};

export type MarketSnapshot = {
  id: MarketId;
  pool: `0x${string}`;
  vault: `0x${string}`;
  alm: `0x${string}`;
  swapFeeModule: `0x${string}`;
  feeSurplus: `0x${string}`;
  riskEngine: `0x${string}`;
  hedgeEscrow: `0x${string}`;
  usdc: `0x${string}`;
  base: `0x${string}`;
  baseSymbol: string;
  tokens: { USDC: TokenMeta; BASE: TokenMeta };
};

function isZero(a: string): boolean {
  return !a || a.toLowerCase() === ZERO.toLowerCase();
}

const PRIMARY_BASE_SYMBOL =
  process.env.NEXT_PUBLIC_PRIMARY_BASE_SYMBOL ?? "PURR";

const SECONDARY_BASE_SYMBOL =
  process.env.NEXT_PUBLIC_SECONDARY_BASE_SYMBOL ??
  process.env.NEXT_PUBLIC_WETH_SYMBOL ??
  "WETH";

/** True when a second stack is deployed (`NEXT_PUBLIC_POOL_WETH` non-zero). Base token/symbol come from env. */
export function isSecondaryMarketAvailable(): boolean {
  return !isZero(ADDRESSES.POOL_WETH);
}

/** @deprecated use isSecondaryMarketAvailable */
export function isWethMarketAvailable(): boolean {
  return isSecondaryMarketAvailable();
}

export function getMarketSnapshot(id: MarketId): MarketSnapshot | null {
  if (id === "secondary" && !isSecondaryMarketAvailable()) return null;

  if (id === "primary") {
    const usdc: `0x${string}` = ADDRESSES.USDC;
    const base: `0x${string}` = ADDRESSES.PURR;
    const sym = PRIMARY_BASE_SYMBOL;
    return {
      id: "primary",
      pool: ADDRESSES.POOL,
      vault: ADDRESSES.VAULT,
      alm: ADDRESSES.ALM,
      swapFeeModule: ADDRESSES.SWAP_FEE_MODULE,
      feeSurplus: ADDRESSES.FEE_SURPLUS,
      riskEngine: ADDRESSES.DELTAFLOW_RISK_ENGINE,
      hedgeEscrow: ADDRESSES.HEDGE_ESCROW,
      usdc,
      base,
      baseSymbol: sym,
      tokens: {
        USDC: {
          address: usdc,
          symbol: "USDC",
          decimals: 6,
          name: "USD Coin",
        },
        BASE: {
          address: base,
          symbol: sym,
          decimals: 18,
          name: sym,
        },
      },
    };
  }

  const usdc: `0x${string}` = ADDRESSES.USDC;
  const base: `0x${string}` = ADDRESSES.WETH;
  const sym = SECONDARY_BASE_SYMBOL;
  return {
    id: "secondary",
    pool: ADDRESSES.POOL_WETH,
    vault: ADDRESSES.VAULT_WETH,
    alm: ADDRESSES.ALM_WETH,
    swapFeeModule: ADDRESSES.SWAP_FEE_MODULE_WETH,
    feeSurplus: ADDRESSES.FEE_SURPLUS_WETH,
    riskEngine: ADDRESSES.DELTAFLOW_RISK_ENGINE_WETH,
    hedgeEscrow: ADDRESSES.HEDGE_ESCROW_WETH,
    usdc,
    base,
    baseSymbol: sym,
    tokens: {
      USDC: {
        address: usdc,
        symbol: "USDC",
        decimals: 6,
        name: "USD Coin",
      },
      BASE: {
        address: base,
        symbol: sym,
        decimals: 18,
        name: sym,
      },
    },
  };
}
