"use client";

import { useReadContracts } from "wagmi";
import { ERC20_ABI } from "@/contracts";
import { useMarket } from "@/app/context/MarketContext";

function readUint8(v: unknown, fallback: number): number {
  if (v === undefined || v === null) return fallback;
  if (typeof v === "bigint") return Number(v);
  if (typeof v === "number" && Number.isFinite(v)) return v;
  return fallback;
}

/**
 * ERC20 `decimals()` for the selected market’s base token and USDC.
 * Hyperliquid spot `szDecimals` (often 5 for PURR) is not the same as EVM ERC20 decimals (usually 18).
 */
export function useMarketEvmDecimals() {
  const { market } = useMarket();
  const base = market.tokens.BASE;
  const usdc = market.tokens.USDC;

  const { data, isLoading, error, refetch } = useReadContracts({
    contracts: [
      {
        address: base.address,
        abi: ERC20_ABI,
        functionName: "decimals",
      },
      {
        address: usdc.address,
        abi: ERC20_ABI,
        functionName: "decimals",
      },
    ],
  });

  const baseDecimals = readUint8(data?.[0]?.result, base.decimals);
  const usdcDecimals = readUint8(data?.[1]?.result, usdc.decimals);

  return { baseDecimals, usdcDecimals, isLoading, error, refetch };
}
