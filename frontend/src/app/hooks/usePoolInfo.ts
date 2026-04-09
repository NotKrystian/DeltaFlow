"use client";

import { useReadContract, useReadContracts } from "wagmi";
import { ALM_ABI, POOL_ABI, ERC20_ABI } from "../lib/contracts";
import { formatUnits } from "viem";
import { useMarket } from "@/app/context/MarketContext";
import { useMarketEvmDecimals } from "./useMarketEvmDecimals";

// Spot price from ALM (USDC per 1 base, scaled per `rawPxScale` on-chain)
export function useSpotPrice() {
  const { market } = useMarket();
  const { data, isLoading, error, refetch } = useReadContract({
    address: market.alm,
    abi: ALM_ABI,
    functionName: "getSpotPriceUsdcPerBase",
  });

  const rawPrice = data ? BigInt(data) : BigInt(0);

  return {
    rawPrice,
    formattedPrice: rawPrice ? Number(rawPrice) / 1e8 : 0,
    isLoading,
    error,
    refetch,
  };
}

// Hook to get pool info for the selected market
export function usePoolInfo() {
  const { market } = useMarket();
  const { data, isLoading, error } = useReadContracts({
    contracts: [
      {
        address: market.pool,
        abi: POOL_ABI,
        functionName: "token0",
      },
      {
        address: market.pool,
        abi: POOL_ABI,
        functionName: "token1",
      },
      {
        address: market.pool,
        abi: POOL_ABI,
        functionName: "alm",
      },
      {
        address: market.pool,
        abi: POOL_ABI,
        functionName: "defaultSwapFeeBips",
      },
    ],
  });

  return {
    token0: data?.[0]?.result as `0x${string}` | undefined,
    token1: data?.[1]?.result as `0x${string}` | undefined,
    alm: data?.[2]?.result as `0x${string}` | undefined,
    feeBips: data?.[3]?.result ? Number(data[3].result) : 0,
    isLoading,
    error,
  };
}

// Balances for base + USDC for the connected user
export function useTokenBalances(userAddress: `0x${string}` | undefined) {
  const { market } = useMarket();
  const base = market.tokens.BASE;
  const usdc = market.tokens.USDC;
  const { baseDecimals, usdcDecimals } = useMarketEvmDecimals();

  const { data, isLoading, error, refetch } = useReadContracts({
    contracts: [
      {
        address: base.address,
        abi: ERC20_ABI,
        functionName: "balanceOf",
        args: userAddress ? [userAddress] : undefined,
      },
      {
        address: usdc.address,
        abi: ERC20_ABI,
        functionName: "balanceOf",
        args: userAddress ? [userAddress] : undefined,
      },
    ],
    query: {
      enabled: !!userAddress,
    },
  });

  return {
    baseBalance: data?.[0]?.result as bigint | undefined,
    usdcBalance: data?.[1]?.result as bigint | undefined,
    purrBalance: data?.[0]?.result as bigint | undefined,
    formattedBase: data?.[0]?.result
      ? formatUnits(data[0].result as bigint, baseDecimals)
      : "0",
    formattedUsdc: data?.[1]?.result
      ? formatUnits(data[1].result as bigint, usdcDecimals)
      : "0",
    formattedPurr: data?.[0]?.result
      ? formatUnits(data[0].result as bigint, baseDecimals)
      : "0",
    isLoading,
    error,
    refetch,
  };
}
